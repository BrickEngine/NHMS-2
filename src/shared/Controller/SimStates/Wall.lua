--[[
    State machine submodule.
    Logic for wall-running movement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local controller = script.Parent.Parent
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local InputManager = require(controller.InputManager)
local PlayerState = require(ReplicatedStorage.Shared.Enums.PlayerState)
local BaseState = require(script.Parent.BaseState)
local PhysCheck = require(controller.Common.PhysCheck)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)

local STATE_ID = PlayerState.ON_WALL

local DISMOUNT_SPEED = 2
local DISTANCE = CharacterDef.PARAMS.MAINCOLL_CF.X * 0.65
local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)

local initialVel = VEC3_ZERO
local initialTargetPos = VEC3_ZERO
local scanVecFunc = nil

-- Create required physics constraints
local function createForces(mdl: Model): {[string]: Instance}
    assert(mdl.PrimaryPart)

    local att = Instance.new("Attachment")
    att.WorldAxis = Vector3.new(0, 1, 0)
    att.Name = "WallAtt"
    att.Parent = mdl.PrimaryPart

    local moveForce = Instance.new("VectorForce", mdl.PrimaryPart)
    moveForce.Name = "WallMoveForce"
    moveForce.Enabled = false
    moveForce.Attachment0 = att
    moveForce.ApplyAtCenterOfMass = true
    moveForce.RelativeTo = Enum.ActuatorRelativeTo.World

    local rotForce = Instance.new("AlignOrientation", mdl.PrimaryPart)
    rotForce.Name = "WallRotForce"
    rotForce.Enabled = false
    rotForce.Attachment0 = att
    rotForce.Mode = Enum.OrientationAlignmentMode.OneAttachment
    rotForce.AlignType = Enum.AlignType.PrimaryAxisParallel
    rotForce.Responsiveness = 200
    rotForce.MaxTorque = math.huge
    rotForce.MaxAngularVelocity = math.huge
    rotForce.ReactionTorqueEnabled = true
    rotForce.PrimaryAxis = VEC3_UP

    local posForce = Instance.new("AlignPosition", mdl.PrimaryPart)
    posForce.Name = "WallPosForce"
    posForce.Enabled = false
    posForce.Attachment0 = att
    posForce.Mode = Enum.PositionAlignmentMode.OneAttachment
    posForce.ForceLimitMode = Enum.ForceLimitMode.PerAxis
    posForce.MaxAxesForce = VEC3_UP * 1000000
    posForce.MaxVelocity = 300--100000
    posForce.Responsiveness = 200
    posForce.ForceRelativeTo = Enum.ActuatorRelativeTo.World
    posForce.Position = mdl.PrimaryPart.CFrame.Position

    return {
        moveForce = moveForce,
        rotForce = rotForce,
        posForce = posForce,
    } :: {[string]: Instance}
end

local function getRightVector(part: BasePart): Vector3
    return part.CFrame.RightVector
end

local function getLeftVector(part: BasePart): Vector3
    return -part.CFrame.RightVector
end

--[[ 
    Calculates whether the wall is to the left or right of the character and returns a corresponding function
    for computing the directional vector for future wall scans
]]
local function getDirFuncFromWallSide(initialVel: Vector3, wallNormal: Vector3): (BasePart) -> Vector3
    local horiVel = Vector3.new(initialVel.X, 0, initialVel.Z)
    local side = (horiVel:Cross(initialVel)):Dot(wallNormal)

    if (side < 0) then
        return getRightVector
    else
        return getLeftVector
    end
end

local function getOffsetPos(hitPos: Vector3, offset: Vector3): Vector3
    return (hitPos + (offset.Unit * DISTANCE))
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Wall = setmetatable({}, BaseState)
Wall.__index = Wall

function Wall.new(...)
    local self = BaseState.new(...) :: BaseState.BaseState

    self.character = self._simulation.character :: Model
    self.forces = createForces(self.character)
    self.id = STATE_ID

    return setmetatable(self, Wall)
end

function Wall:stateEnter(params: any?)
    if (not self.forces) then
        warn("No forces to enable in state: 'Ground'"); return
    end
    for _, f: Constraint in self.forces do
        f.Enabled = true
    end

    local primaryPart: BasePart = self.character.PrimaryPart
    local hitNormal: Vector3 = params.normal
    local hitPos: Vector3 = params.position
    assert(primaryPart, `Missing PrimaryPart of character '{self.character.name}'`)
    assert(hitNormal, "Missing required normal parameters")
    assert(hitPos, "Missing required position parameters")

    initialVel = primaryPart.AssemblyLinearVelocity
    scanVecFunc = getDirFuncFromWallSide(initialVel, hitNormal)
    initialTargetPos = getOffsetPos(hitPos, hitNormal)

    primaryPart.CFrame = CFrame.new(initialTargetPos)
    print((initialTargetPos - params.position).Magnitude)
end

function Wall:stateLeave()
    if (not self.forces) then
        return
    end
    for _, f: Constraint in self.forces do
        f.Enabled = false
    end

    local primaryPart: BasePart = self.character.PrimaryPart
    assert(primaryPart, `Missing PrimaryPart of character '{self.character.name}'`)

    primaryPart.AssemblyLinearVelocity = VEC3_ZERO

    warn("WALL LEFT")
end

function Wall:updateMove(dt: number, normal: Vector3, bankAngle: number)
    
end

function Wall:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame = Workspace.CurrentCamera.CFrame
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)
    local g = Workspace.Gravity
    local mass = primaryPart.AssemblyMass

    local scanDirVec = scanVecFunc(primaryPart)
    scanDirVec = Vector3.new(scanDirVec.X, 0, scanDirVec.Z)

    -- Do physics checks
    local groundData: PhysCheck.groundData = PhysCheck.checkFloor(currPos, PHYS_RADIUS, HIP_HEIGHT, 0.1)
    local wallData: PhysCheck.wallData
    if (currHoriVel.Magnitude < 0.1) then
        wallData = PhysCheck.defaultWallData()
    else
        wallData = PhysCheck.checkWall(currPos, scanDirVec, PHYS_RADIUS, HIP_HEIGHT)
    end
    self.grounded = groundData.grounded
    self.nearWall = wallData.nearWall

    if (self.grounded or not self.nearWall or currHoriVel.magnitude < DISMOUNT_SPEED) then
        self._simulation:transitionState(PlayerState.GROUNDED)
    end

    -- if (count > 0.5) then
    --     self._simulation:transitionState(PlayerState.GROUNDED)
    -- end

    -- Update wall movement
    if (self.nearWall) then
        self:updateMove(dt, wallData.normal, wallData.wallBankAngle)
    end
    self.forces.posForce.Position = VEC3_UP * 6

    -- Update playermodel rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        )
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO

    -- State transitions
    if (self.inWater) then
        self._simulation:transitionState(PlayerState.IN_WATER)
    elseif (self.onGround) then
        self._simulation:transitionState(PlayerState.GROUNDED)
    end
end

function Wall:destroy()
    if (self.forces) then
        for i, _ in pairs(self.forces) do
            (self.forces[i] :: Instance):Destroy()
        end
    end
    setmetatable(self, nil)
end

return Wall
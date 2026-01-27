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
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

local STATE_ID = PlayerState.ON_WALL

local DISMOUNT_SPEED = 10.0 -- studs/s (should be lower than mount speed in the Ground state)
local JUNP_INP_COOLDOWN = 0.1 -- seconds
local JUMP_HEIGHT = 8.0
local JUMP_DIST_FAC = 18.0
local BANK_MIN = math.rad(75.0) -- min dismount wall angle
local BANK_MAX = math.rad(105.0) -- max dismount wall angle
local SCAN_ANGLE = math.rad(76.0) -- angle offset for left / right wall scans
-- local MOVE_DT = 0.05 -- time delta for move accel
-- local MOVE_DAMP = 0.1 -- equivalent to MOVE_DAMP in the Ground module
-- local WALL_SPEED_FAC = 0.038
local OMEGA = 7.5 -- constant for the updateMove spring
local WALL_OFFSET = CharacterDef.PARAMS.MAINCOLL_SIZE.X * 0.54
local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X

local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)

local initialVel = VEC3_ZERO
local jumpInpDebounce = JUNP_INP_COOLDOWN
local peakedJumpAfterEntry = false
local jumpKeyPressedInit = false
local isRightSideWall = false
local scanVecRotFunc = nil
local normVecRotFunc = nil

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

local function rotateNormVecLeft(vec: Vector3): Vector3
    return Vector3.new(vec.Z, vec.Y, -vec.X)
end

local function rotateNormVecRight(vec: Vector3): Vector3
    return Vector3.new(-vec.Z, vec.Y, vec.X)
end

local function rotateVecLeft(vec: Vector3): Vector3
    return MathUtil.rotateAroundAxisVec3(vec, VEC3_UP, SCAN_ANGLE)
end

local function rotateVecRight(vec: Vector3): Vector3
    return MathUtil.rotateAroundAxisVec3(vec, VEC3_UP, -SCAN_ANGLE)
end

--[[ 
    Calculates whether the wall is to the left or right of the character and returns a corresponding function
    for computing the directional vector for future wall scans
]]
local function getDirFuncFromWallSide(initialDir: Vector3, wallNormal: Vector3): (Vector3) -> Vector3
    local horiDir = Vector3.new(initialDir.X, 0, initialDir.Z)
    local right = horiDir:Cross(VEC3_UP)
    local side = right:Dot(wallNormal)

    if (side < 0) then
        isRightSideWall = true
        return rotateVecRight, rotateNormVecRight
    else
        isRightSideWall = false
        return rotateVecLeft, rotateNormVecLeft
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Wall = setmetatable({}, BaseState)
Wall.__index = Wall

function Wall.new(...)
    local self = BaseState.new(...) :: BaseState.BaseState

    self.id = STATE_ID

    self.character = self._simulation.character :: Model
    self.forces = createForces(self.character)

    self.animation = self._simulation.animation

    return setmetatable(self, Wall)
end

function Wall:stateEnter(params: any?)
    local primaryPart: BasePart = self.character.PrimaryPart
    local hitNormal: Vector3 = params.normal
    local hitPos: Vector3 = params.position
    local horiCamDir = Workspace.CurrentCamera.CFrame.LookVector
    horiCamDir = Vector3.new(horiCamDir.X, 0, horiCamDir.Z).Unit

    initialVel = primaryPart.AssemblyLinearVelocity
    local initialHoriVel = Vector3.new(initialVel.X, 0, initialVel.Z)

    assert(primaryPart, `Missing PrimaryPart of character '{self.character.name}'`)
    assert(hitNormal, "Missing required normal parameters")
    assert(hitPos, "Missing required position parameters")
    assert(initialVel.Magnitude > 0.01, "Minimum velocity required")

    --currWallVelFac = initialVel.Magnitude
    scanVecRotFunc, normVecRotFunc = getDirFuncFromWallSide(initialHoriVel, hitNormal)

    local projWallVel = normVecRotFunc(hitNormal).Unit * initialVel.Magnitude
    primaryPart:ApplyImpulse(
        (projWallVel - Vector3.new(initialVel.X, 0, initialVel.Z)) * primaryPart.AssemblyMass
    )

    self.isRightSideWall = isRightSideWall
    jumpInpDebounce = JUNP_INP_COOLDOWN

    if (not self.forces) then
        warn("No forces to enable in state: 'Ground'"); return
    end
    self.forces.moveForce.Enabled = true
    self.forces.rotForce.Enabled = true
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

    jumpKeyPressedInit = InputManager:getJumpKeyDown()
    peakedJumpAfterEntry = false
    self.wallTime = 0
end

-- Registers jump input and transitions to ground, when a dismount is executed
function Wall:handleDismount(wallNorm: Vector3)
    if (jumpKeyPressedInit) then
        jumpKeyPressedInit = InputManager:getJumpKeyDown()
        return
    end
    if (not InputManager:getJumpKeyDown() or jumpInpDebounce > 0) then
        return
    end

    local primaryPart: BasePart = self.character.PrimaryPart
    local mass = primaryPart.AssemblyMass
    local camDir =  Workspace.CurrentCamera.CFrame.lookVector
    local horiCamDir = Vector3.new(camDir.X, 0, camDir.Z).Unit

    local impulse do
        --local movDir = normVecRotFunc(wallNorm).Unit
        --local dirFac = 2 - math.clamp(horiCamDir:Dot(movDir), 0, 1)
        local dirFac = 1.0 + math.clamp(wallNorm:Dot(horiCamDir), 0, 1)
        local horiAccel = wallNorm * dirFac * JUMP_DIST_FAC
        local targetJumpFac = math.clamp(VEC3_UP:Dot(camDir), -0.4, 0.4) * 1.65

        local vertAccel = 
            math.sqrt(Workspace.Gravity * 2 * JUMP_HEIGHT) * targetJumpFac
            + math.sqrt(Workspace.Gravity * JUMP_HEIGHT * 1.2)
        vertAccel *= VEC3_UP
        local currVertVel = VEC3_UP * primaryPart.AssemblyLinearVelocity.Y

        impulse = (horiAccel + vertAccel - currVertVel) * mass
    end

    self.forces.moveForce.Enabled = false
    self.forces.posForce.Enabled = false
    primaryPart:ApplyImpulse(impulse)

    self._simulation:transitionState(PlayerState.GROUNDED)
end

-- Updates posForce
function Wall:updateVerticalAnchor(dt: number)
    if (peakedJumpAfterEntry) then return end

    local primaryPart: BasePart = self.character.PrimaryPart
    local currVel = primaryPart.AssemblyLinearVelocity
    
    peakedJumpAfterEntry = currVel.Y < 0.1

    if (peakedJumpAfterEntry) then
        self.forces.posForce.Position = primaryPart.CFrame.Position
        self.forces.posForce.Enabled = true
    end
end

-- Updates moveForce
function Wall:updateMove(dt: number, targetPos: Vector3, normal: Vector3, bankAngle: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local currHoriVel = primaryPart.AssemblyLinearVelocity
    currHoriVel = Vector3.new(currHoriVel.X, 0, currHoriVel.Z)

    local currPos = primaryPart.CFrame.Position
    local offsTargetPos = targetPos + normal * WALL_OFFSET
    local mass = primaryPart.AssemblyMass

    local horiCamDir = Workspace.CurrentCamera.CFrame.LookVector
    horiCamDir = Vector3.new(horiCamDir.X, 0, horiCamDir.Z).Unit

    local stiffness = mass * OMEGA * OMEGA
    local damping = 0.45 * mass * OMEGA

    local accel = (offsTargetPos - currPos):Dot(-normal) * stiffness
    local dampAccel = damping * currHoriVel:Dot(-normal)
    local accelVec = -normal * (accel - dampAccel)

    print(math.round((currPos - targetPos).Magnitude))

    self.forces.moveForce.Force = accelVec * mass
end

------------------------------------------------------------------------------------------------------------------------
-- Wall update
------------------------------------------------------------------------------------------------------------------------

function Wall:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame = Workspace.CurrentCamera.CFrame
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)

    -- Physics checks
    local groundData: PhysCheck.groundData = PhysCheck.checkFloor(currPos, PHYS_RADIUS, HIP_HEIGHT, 0.1)
    local wallData: PhysCheck.wallData
    if (currHoriVel.Magnitude < 0.1) then
        wallData = PhysCheck.defaultWallData()
    else
        local scanDirVec = scanVecRotFunc(currHoriVel).Unit --currHoriVel.Unit) --primaryPart.CFrame.LookVector
        wallData = PhysCheck.checkWall(currPos, scanDirVec, PHYS_RADIUS, HIP_HEIGHT)
    end
    self.grounded = groundData.grounded
    self.nearWall = wallData.nearWall

    if (self.nearWall and peakedJumpAfterEntry) then
        self.forces.posForce.Enabled = true
    else
        self.forces.posForce.Enabled = false
    end

    -- State transitions
    do
        local bankAngleExceeded = wallData.wallBankAngle < BANK_MIN or wallData.wallBankAngle > BANK_MAX

        if (self.inWater) then
            self._simulation:transitionState(PlayerState.IN_WATER); return
        elseif (
            self.grounded or (not self.nearWall) 
            or currHoriVel.Magnitude < DISMOUNT_SPEED or bankAngleExceeded
        ) then
            self._simulation:transitionState(PlayerState.GROUNDED); return
        end
    end

    -- Update horizontal moveForce
    self:updateMove(dt, wallData.position, wallData.normal, wallData.wallBankAngle)
    -- Update posForce
    self:updateVerticalAnchor(dt)
    -- Check for jump input
    self:handleDismount(wallData.normal)

    -- Update playermodel rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        )
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO

    jumpInpDebounce -= dt
    jumpInpDebounce = math.max(jumpInpDebounce, 0)
    self.wallTime += dt
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
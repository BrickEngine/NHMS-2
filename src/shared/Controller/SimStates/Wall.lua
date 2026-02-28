--[[
    State machine submodule.
    Logic for wall-running movement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local controller = script.Parent.Parent
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local InputManager = require(controller.InputManager)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local SoundManager = require(ReplicatedStorage.Shared.SoundManager)
local BaseState = require(script.Parent.BaseState)
local PhysCheck = require(controller.Common.PhysCheck)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

local STATE_ID = PlayerStateId.WALL

local DISMOUNT_SPEED = 0.01--2.4 -- studs/s (should be lower than mount speed in the Ground state)

local JUNP_INP_COOLDOWN = 0.1 -- seconds
local JUMP_HEIGHT = 8.0
local JUMP_DIST_FAC = 18.0

local BANK_MIN = math.rad(75.0) -- min dismount wall angle
local BANK_MAX = math.rad(105.0) -- max dismount wall angle
local SCAN_ANGLE = math.rad(70.0) -- angle offset for left / right wall scans

-- max angle difference between two out of all hit wall normals which, if exceeded, will result in a dismount
local MAX_ANGLE_DIFF = math.rad(87.5)
-- force scaling for how much force should be applied along the negative wall normal relative to movement speed
local WALL_FORCE_STRENGTH_FAC = 10.75
-- max force to be applied by the linear velocity along the wall
local MAX_LIN_VEL_FORCE = 400000

local SLIDE_FAC = 50.25 -- distance scaling for how much a player slides per frame
local MANEUV_FAC = 0.98 -- wall maneuverability factor scaled with velocity
local START_SLIDE_VEL = 45.0 -- studs/s - velocity at which a player starts to slide
local WALL_MAX_SPEED = 125.0 -- studs/s, max speed on the wall
local BOOST_FAC = 1.38 -- by how much to boost the wall velocity on enter
local WALL_SPEED_LOSS_FAC = 9.5 -- how much speed is reduced each phys update on the wall

local PLAY_WALL_SOUNDS = true

local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X

local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)

local initialVel = VEC3_ZERO
local currLineDirVel = 0
local jumpInpDebounce = JUNP_INP_COOLDOWN
local peakedJumpAfterEntry = false
local jumpKeyPressedOnEnter = false
local isRightSideWall = false
local scanVecRotFunc = nil
local normVecRotFunc = nil

-- Create required physics constraints
local function createForces(mdl: Model): {[string]: Instance}
    assert(mdl.PrimaryPart)

    local att = Instance.new("Attachment", mdl.PrimaryPart)
    att.Name = "WallAtt"
    att.WorldAxis = VEC3_UP

    local moveForce = Instance.new("VectorForce", mdl.PrimaryPart)
    moveForce.Name = "WallMoveForce"
    moveForce.Enabled = false
    moveForce.Attachment0 = att
    moveForce.ApplyAtCenterOfMass = true
    moveForce.RelativeTo = Enum.ActuatorRelativeTo.World

    local linVelocity = Instance.new("LinearVelocity", mdl.PrimaryPart)
    linVelocity.Name = "WallLinVelocity"
    linVelocity.Enabled = false
    linVelocity.Attachment0 = att
    linVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
    linVelocity.ForceLimitsEnabled = true
    linVelocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
    linVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
    linVelocity.MaxForce = MAX_LIN_VEL_FORCE
    linVelocity.LineVelocity = 0

    local posForce = Instance.new("AlignPosition", mdl.PrimaryPart)
    posForce.Name = "VertWallPosForce"
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
        linVelocity = linVelocity,
        posForce = posForce
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
local function getDirFuncFromWallSide(initialDir: Vector3, wallNorm: Vector3): (Vector3) -> any
    local horiDir = Vector3.new(initialDir.X, 0, initialDir.Z)
    local right = horiDir:Cross(VEC3_UP)
    local side = right:Dot(wallNorm)

    if (side < 0) then
        isRightSideWall = true
        return rotateVecRight, rotateNormVecRight
    else
        isRightSideWall = false
        return rotateVecLeft, rotateNormVecLeft
    end
end

-- local function getDirFacFromWallSide(initialDir: Vector3, wallNorm: Vector3): number
--     local horiDir = Vector3.new(initialDir.X, 0, initialDir.Z)
--     local right = horiDir:Cross(VEC3_UP)
--     local side = right:Dot(wallNorm)

--     return (side < 0) and 1 or 0
-- end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Wall = setmetatable({}, BaseState)
Wall.__index = Wall

function Wall.new(...)
    local self = BaseState.new(...) :: BaseState.BaseState

    self.id = STATE_ID

    self.shared = self._simulation.stateShared
    self.character = self._simulation.character :: Model
    self.forces = createForces(self.character)
    self.animation = self._simulation.animation

    return setmetatable(self, Wall)
end

function Wall:stateEnter(stateId: number, params: any?)
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
    assert(initialVel.Magnitude > 0.01, "Initial velocity mag too small")

    scanVecRotFunc, normVecRotFunc = getDirFuncFromWallSide(initialHoriVel, hitNormal)

    --local projInitialVel = MathUtil.projectOnPlaneVec3(initialHoriVel, hitNormal)
    local wallVel: Vector3 = normVecRotFunc(hitNormal).Unit * initialVel.Magnitude * BOOST_FAC

    if (wallVel.Magnitude > WALL_MAX_SPEED) then
        wallVel = wallVel.Unit * WALL_MAX_SPEED
    end
    currLineDirVel = wallVel.Magnitude
    self.forces.linVelocity.LineDirection = wallVel.Unit
    self.forces.linVelocity.LineVelocity = wallVel.Magnitude

    self.shared.isRightSideWall = isRightSideWall
    jumpInpDebounce = JUNP_INP_COOLDOWN

    if (not self.forces) then
        warn("No forces to enable in state: 'Ground'"); return
    end
    self.forces.moveForce.Enabled = true
    self.forces.linVelocity.Enabled = true

    -- check if jump key is pressed on state enter
    jumpKeyPressedOnEnter = InputManager:getJumpKeyDown()

    -- play entry sounds and start looped wall-run sound
    if (PLAY_WALL_SOUNDS) then
        local soundArr = {
            SoundManager.SOUND_ITEMS.WALL_ENTER_0,
            SoundManager.SOUND_ITEMS.WALL_ENTER_1
        }
        local chosen = soundArr[math.random(1, 2)]
        SoundManager:updateGlobalSound(chosen, true)
        -- looped sound
        SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.WALL_SLIDE, true)
    end
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

    peakedJumpAfterEntry = false
    self.shared.wallTime = 0

    SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.WALL_SLIDE, false)
end

-- Registers jump input and transitions to ground, when a dismount is executed
function Wall:handleDismount(dt: number, wallNorm: Vector3)
    -- do not dismount if the jump key was held down when entering the state
    if (jumpKeyPressedOnEnter) then
        jumpKeyPressedOnEnter = InputManager:getJumpKeyDown()
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

    -- play dismount sound
    if (PLAY_WALL_SOUNDS) then
        SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.JUMP, true)
    end

    self._simulation:transitionState(PlayerStateId.GROUND)
end

-- Updates posForce
function Wall:updateVerticalAnchor(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local currVel = primaryPart.AssemblyLinearVelocity
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)

    if (peakedJumpAfterEntry) then
        local camLooKVec = Workspace.CurrentCamera.CFrame.LookVector
        local cappedVelFac = math.min(currVel.Magnitude * 25, 600.0)

        local camUpFac = math.clamp(VEC3_UP:Dot(camLooKVec), -0.4, 0.4) * MANEUV_FAC * currVel.Magnitude
        local forceDownFac = 0
        if (currHoriVel.Magnitude < START_SLIDE_VEL) then
            forceDownFac = Workspace.Gravity * SLIDE_FAC / cappedVelFac
        end

        self.forces.posForce.Position = self.forces.posForce.Position + VEC3_UP * (camUpFac - forceDownFac) * dt
        return
    end
    
    peakedJumpAfterEntry = currVel.Y < 0.1

    if (peakedJumpAfterEntry) then
        self.forces.posForce.Position = primaryPart.CFrame.Position
        self.forces.posForce.Enabled = true
    end
end

-- Updates moveForce
function Wall:updateWallForce(dt: number, targetPos: Vector3, normal: Vector3)
    local primaryPart: BasePart = self.character.PrimaryPart

    -- calc wall-clinging force
    local velFac = 1.0 + primaryPart.AssemblyLinearVelocity.Magnitude
    local mass = primaryPart.AssemblyMass
    self.forces.moveForce.Force = -normal * mass * WALL_FORCE_STRENGTH_FAC * velFac

    -- calc velocity along wall
    local flyDir: Vector3 = normVecRotFunc(normal).Unit
    self.forces.linVelocity.LineDirection = flyDir
    self.forces.linVelocity.LineVelocity = currLineDirVel

    currLineDirVel -= dt * WALL_SPEED_LOSS_FAC
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

    -- physics checks
    local groundData: PhysCheck.groundData = PhysCheck.checkFloor(currPos, PHYS_RADIUS, HIP_HEIGHT, 0.1)
    local wallData: PhysCheck.wallData
    if (currHoriVel.Magnitude < 0.1) then
        wallData = PhysCheck.defaultWallData()
    else
        local scanDirVec = scanVecRotFunc(currHoriVel).Unit --currHoriVel.Unit) --primaryPart.CFrame.LookVector
        wallData = PhysCheck.checkWall(currPos, scanDirVec, PHYS_RADIUS, HIP_HEIGHT)
    end

    local waterData: PhysCheck.waterData = 
        PhysCheck.checkWater(primaryPart.Position, PHYS_RADIUS, self.shared.buoySensor)

    self.shared.grounded = groundData.grounded
    self.shared.nearWall = wallData.nearWall
    self.shared.inWater = waterData.inWater

    if (self.shared.nearWall and peakedJumpAfterEntry) then
        self.forces.posForce.Enabled = true
    else
        self.forces.posForce.Enabled = false
    end

    -- State transitions
    do
        local bankAngleExceeded = wallData.bankAngle < BANK_MIN or wallData.bankAngle > BANK_MAX

        if (self.shared.inWater) then
            self._simulation:transitionState(PlayerStateId.WATER); return
        elseif (
            self.shared.grounded or not self.shared.nearWall
            or currHoriVel.Magnitude < DISMOUNT_SPEED or bankAngleExceeded
            or wallData.maxAngleDiff > MAX_ANGLE_DIFF
        ) then
            self._simulation:transitionState(PlayerStateId.GROUND); return
        end
    end

    -- Update horizontal moveForce
    self:updateWallForce(dt, wallData.position, wallData.normal)
    -- Update posForce
    self:updateVerticalAnchor(dt)
    -- Check for jump input
    self:handleDismount(dt, wallData.normal)

    -- Update playermodel rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        )
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO

    jumpInpDebounce -= dt
    jumpInpDebounce = math.max(jumpInpDebounce, 0)
    self.shared.wallTime += dt
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
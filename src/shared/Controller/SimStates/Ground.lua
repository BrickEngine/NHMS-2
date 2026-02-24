--[[
    State machine submodule.
    Logic for ground and air movement, jumping and related abilities.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local controller = script.Parent.Parent
local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local InputManager = require(controller.InputManager)
local SoundManager = require(ReplicatedStorage.Shared.SoundManager)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local BaseState = require(controller.SimStates.BaseState)
local PhysCheck = require(controller.Common.PhysCheck)

local STATE_ID = PlayerStateId.GROUNDED

-- General physics config
local MOVE_SPEED = 1.75
local DASH_SPEED = 3.2
local MIN_WALL_MOUNT_SPEED = 12.0 -- studs/s
local ALLOW_IMM_WALL_MOUNT = true -- whether to allow repeated Wall state transitions
local MUST_LOOK_AT_WALL = false -- whether to allow wall mounting without looking at the wall
local GND_CLEAR_DIST = 0.45
local MAX_INCLINE = math.rad(70) -- radiants
local JUMP_HEIGHT = 6
local JUMP_DELAY = 0.28
local DASH_TIME = 1.6 -- seconds
local DASH_COOLDOWN_TIME = 0.8 -- seconds
local MOVE_DAMP = 0.4 -- lower value ~ more rigid movement (do not set too low; breaks at low framerates)
local DASH_DAMP = 0.1 -- equivalent to MOVE_DAMP
local MOVE_DT = 0.05 -- time delta for move accel

local FORCE_STEPUP = false -- whether the player will be forced up steep inclines, if too low to the ground
local GND_FORCE_DIST = 0.1 -- height at which player will be forced up, if FORCE_STEUP is true

local PLAY_JUMP_SOUND = true -- To be removed later

-- Animation
local ANIM_THRESHHOLD = 0.1 -- Studs/s
local ANIM_SPEED_FAC = 0.06

local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X
local COLL_HEIGHT = CharacterDef.PARAMS.MAINCOLL_SIZE.X
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)
local VEC3_RIGHT = Vector3.new(0, 0, 1)

type Counter = {
    t: number,
    cooldown: number
}

------------------------------------------------------------------------------------------------------------------------
-- Local vars
local ray_params_gnd = RaycastParams.new()
ray_params_gnd.CollisionGroup = CollisionGroup.PLAYER
ray_params_gnd.FilterType = Enum.RaycastFilterType.Exclude
ray_params_gnd.IgnoreWater = true
ray_params_gnd.RespectCanCollide = true

local wasGroundedOnce = false

local lastDashInput = false
local dash = {
    t = 0,
    cooldown = 0
} :: Counter

local j_lastDown = false
local j_Delay = 0
local lastYPos = 0
local jumped = false
local jumpSignal = false
local offGroundTime = 0
local inStateTime = 0

-- Create required physics constraints
local function createForces(mdl: Model): {[string]: Instance}
    assert(mdl.PrimaryPart)

    local att = Instance.new("Attachment")
    att.WorldAxis = Vector3.new(0, 1, 0)
    att.Name = "Ground"
    att.Parent = mdl.PrimaryPart

    local moveForce = Instance.new("VectorForce", mdl.PrimaryPart)
    moveForce.Enabled = false
    moveForce.Attachment0 = att
    moveForce.ApplyAtCenterOfMass = true
    moveForce.RelativeTo = Enum.ActuatorRelativeTo.World

    local rotForce = Instance.new("AlignOrientation", mdl.PrimaryPart)
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
    posForce.Enabled = false
    posForce.Attachment0 = att
    posForce.Mode = Enum.PositionAlignmentMode.OneAttachment
    posForce.ForceLimitMode = Enum.ForceLimitMode.PerAxis
    posForce.MaxAxesForce = Vector3.zero
    posForce.MaxVelocity = 150--100000
    posForce.Responsiveness = 195
    posForce.ForceRelativeTo = Enum.ActuatorRelativeTo.World
    posForce.Position = mdl.PrimaryPart.CFrame.Position

    return {
        moveForce = moveForce,
        rotForce = rotForce,
        posForce = posForce,
    } :: {[string]: Instance}
end

local function getCFrameRelMoveVec(camCFrame: CFrame, relativeVec: Vector3): Vector3
    return CFrame.new(
        VEC3_ZERO,
        Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        ).Unit
    ):VectorToWorldSpace(relativeVec)
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Ground = setmetatable({}, BaseState)
Ground.__index = Ground

function Ground.new(...)
    local self = BaseState.new(...) :: BaseState.BaseState

    self.id = STATE_ID

    self.character = self._simulation.character :: Model
    self.forces = createForces(self.character)
    self.isDashing = false

    self.animation = self._simulation.animation

    --ray_params_gnd.FilterDescendantsInstances = self.character:GetChildren()

    return setmetatable(self, Ground)
end

function Ground:stateEnter()
    if (not self.forces) then
        warn("No forces to enable in state: 'Ground'"); return
    end
    self.forces.moveForce.Enabled = true
    self.forces.rotForce.Enabled = true

    dash = {
        t = 0,
        cooldown = 0
    }
    inStateTime = 0

    self.animation:setState("Idle")
end

function Ground:stateLeave()
    if (not self.forces) then
        return
    end
    for _, f in self.forces do
        f.Enabled = false
    end
    self.isDashing = false
    ClientRoot.setIsDashing(self.isDashing)

    wasGroundedOnce = false
end

function Ground:updateJump(dt: number, override: boolean?)
    -- manage input cooldown for the jump action
    local function updateJumpTime()
        if (InputManager:getJumpKeyDown()) then
            if (not j_lastDown and j_Delay <= 0) then
                j_lastDown = true
                j_Delay = JUMP_DELAY
                jumpSignal = true
                return
            end
        else
            j_lastDown = false
        end

        j_Delay = math.max(j_Delay - dt, 0)
        jumpSignal = false
    end

    updateJumpTime()

    local primaryPart: BasePart = self.character.PrimaryPart
    local currRootPos = primaryPart.CFrame.Position

    if (self.grounded) then
        if ((j_Delay <= 0) or
            (jumped and currRootPos.Y < lastYPos)
        ) then
            self.forces.posForce.Enabled = true
            jumped = false
        end

        -- execute jump
        if (jumpSignal or override) then
            if (PLAY_JUMP_SOUND) then
                SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.JUMP, true) 
            end

            self.forces.posForce.Enabled = false

            local jumpInitVel: number = math.sqrt(Workspace.Gravity * 2 * JUMP_HEIGHT)
            primaryPart:ApplyImpulse(
                VEC3_UP * (jumpInitVel - primaryPart.AssemblyLinearVelocity.Y) * primaryPart.AssemblyMass)
            jumped = true
        end
    end

    lastYPos = currRootPos.Y
end

-- Checks if conditions to execute a dash are met
function Ground:updateDash(dt: number)
    local input = InputManager:getDashKeyDown()
    local dashImpulse = false

    if (dash.cooldown <= 0) then
        dashImpulse = input and not lastDashInput

        if (self.isDashing and (not input or dash.t <= 0)) then
            dash.t = 0
            dash.cooldown = DASH_COOLDOWN_TIME
            self.isDashing = false
        end
    end

    if (dashImpulse) then
        dash.t = DASH_TIME
        self.isDashing = true
    end

    dash.cooldown = math.max(dash.cooldown - dt, 0)
    if (self.isDashing) then
        dash.t = math.max(dash.t - dt, 0)
    end

    lastDashInput = input
end

-- Updates horizontal movement force
function Ground:updateMove(dt: number, rawMoveDir: Vector3, normal: Vector3, normAngle: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame = Workspace.CurrentCamera.CFrame
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local mass = primaryPart.AssemblyMass
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)

    local accelVec, moveDirVec, target
    if (self.isDashing and not (normAngle > MAX_INCLINE)) then
        moveDirVec = getCFrameRelMoveVec(camCFrame, VEC3_RIGHT)
        target = currPos - moveDirVec * DASH_SPEED
        accelVec = 2 * ((target - currPos) - currHoriVel * MOVE_DT)/(MOVE_DT * DASH_DAMP)
    else
        moveDirVec = rawMoveDir
        target = currPos - moveDirVec * MOVE_SPEED
        accelVec = 2 * ((target - currPos) - currHoriVel * MOVE_DT)/(MOVE_DT * MOVE_DAMP)
    end
    self.forces.moveForce.Force = accelVec * mass

    if (not self.grounded and not self.isDashing) then
        self.forces.moveForce.Force *= 0.1
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Ground update
------------------------------------------------------------------------------------------------------------------------
function Ground:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camera = Workspace.CurrentCamera
    local camDir = camera.CFrame.LookVector
    local rawMoveDir = getCFrameRelMoveVec(camera.CFrame, InputManager:getMoveVec())
    local horiCamDir = Vector3.new(camDir.X, 0, camDir.Z)
    local currVel = primaryPart.AssemblyLinearVelocity
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)
    local currPos = primaryPart.CFrame.Position
    local grav = Workspace.Gravity
    local mass = primaryPart.AssemblyMass

    -- do physics checks
    local groundData: PhysCheck.groundData = PhysCheck.checkFloor(
        currPos, PHYS_RADIUS, HIP_HEIGHT, GND_CLEAR_DIST
    )
    local wallData: PhysCheck.wallData
    
    if (currHoriVel.Magnitude < 0.1) then
        wallData = PhysCheck.defaultWallData()
    else
        local scanDir = self.isDashing and horiCamDir or currHoriVel
        wallData = PhysCheck.checkWall(currPos, scanDir, PHYS_RADIUS, HIP_HEIGHT)

        -- if scanDir delivers no results, check again with the raw input dir
        if (not wallData.nearWall and rawMoveDir.Magnitude > 0.1 
            and inStateTime > 0.5 and wasGroundedOnce
        ) then
            wallData = PhysCheck.checkWall(currPos, -rawMoveDir, PHYS_RADIUS, HIP_HEIGHT)
        end
    end

    self.grounded = groundData.grounded
    self.nearWall = wallData.nearWall

    ClientRoot.setIsGrounded(self.grounded)

    if (self.grounded) then
        local targetPosY = groundData.gndHeight + HIP_HEIGHT

        -- scale force with cubed vertical velocity to compensate for high falls
        self.forces.posForce.MaxAxesForce = mass * (grav * 20 + currVel.Y * currVel.Y) * VEC3_UP
        self.forces.posForce.Position = Vector3.new(0, targetPosY, 0)

        if (PLAY_JUMP_SOUND and offGroundTime >= 0.2) then
            SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.FLOOR_HIT, true)
        end

        -- force character to get more ground distance, if too close to ground
        if (FORCE_STEPUP) then
            local closestPosDiff = math.abs(groundData.closestPos.Y - primaryPart.CFrame.Position.Y)

            if (closestPosDiff < GND_FORCE_DIST) then
                local isSteep = false

                -- step-up only possible, if there is no low ceiling and no steep slope
                local upRay = Workspace:Raycast(
                    groundData.closestPos, VEC3_UP * (HIP_HEIGHT + COLL_HEIGHT + 0.05), ray_params_gnd
                ) :: RaycastResult
                -- TODO: get normal from gndPhysData returned part directly
                local downRay = Workspace:Raycast(
                    groundData.closestPos + VEC3_UP * 0.1, -VEC3_UP, ray_params_gnd
                ) :: RaycastResult

                if (downRay and downRay.Normal) then
                    local incAng = math.acos(downRay.Normal.Unit:Dot(VEC3_UP))
                    isSteep = incAng > MAX_INCLINE
                end
                if (not (isSteep or upRay)) then
                    local newPosOffset = VEC3_UP * (closestPosDiff + HIP_HEIGHT)

                    primaryPart.CFrame *= CFrame.new(newPosOffset)
                    self.forces.posForce.Position = newPosOffset
                end
            end
        end

        wasGroundedOnce = true
    else
        self.forces.posForce.Enabled = false
    end

    -- update jumping
    self:updateJump(dt)

    -- update dashing checks, set ClientRoot var
    self:updateDash(dt)
    ClientRoot.setIsDashing(self.isDashing)

    -- update movement and switch to dash, if dashing
    self:updateMove(dt, rawMoveDir, groundData.normal, groundData.normalAngle)

    -- update animation
    if (currHoriVel.Magnitude >= ANIM_THRESHHOLD) then
        self.animation:setState("Walk")
        self.animation:adjustSpeed(currHoriVel.Magnitude * ANIM_SPEED_FAC)
    else
        self.animation:setState("Idle")
        self.animation:adjustSpeed(1)
    end

    -- update playermodel rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, horiCamDir
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO

    -- state transitions
    do
        local canMountWall
        if (ALLOW_IMM_WALL_MOUNT) then
            canMountWall = true
        else
            canMountWall = wasGroundedOnce
        end

        local facingWall = false
        local projWallVel = VEC3_ZERO
        if (wallData.normal and wallData.normal ~= VEC3_ZERO) then
            projWallVel = MathUtil.projectOnPlaneVec3(currHoriVel, wallData.normal).Unit * currHoriVel.Magnitude
            facingWall = wallData.normal:Dot(horiCamDir) < 0
        end
        if (not MUST_LOOK_AT_WALL) then
            facingWall = true
        end

        local wallConditions = 
            not self.grounded and projWallVel.Magnitude >= MIN_WALL_MOUNT_SPEED 
            and canMountWall and facingWall

        if (self.inWater) then
            self._simulation:transitionState(PlayerStateId.IN_WATER); return
        elseif (self.nearWall and wallConditions) then
            self._simulation:transitionState(
                PlayerStateId.ON_WALL, 
                {
                    normal = wallData.normal, 
                    position = wallData.position
                }
            ); return
        end 
    end

    if (not self.grounded) then
        offGroundTime += dt
    else
        offGroundTime = 0
    end
    inStateTime += dt
end

function Ground:destroy()
    if (self.forces) then
        for i, _ in pairs(self.forces) do
            (self.forces[i] :: Instance):Destroy()
        end
    end
    setmetatable(self, nil)
end

return Ground
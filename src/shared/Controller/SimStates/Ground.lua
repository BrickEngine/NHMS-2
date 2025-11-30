--[[
    Statemachine submodule.
    Logic for ground and air movement, jumping and related abilities.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local controller = script.Parent.Parent
local GameClient = require(ReplicatedStorage.Shared.GameClient)
local Global = require(ReplicatedStorage.Shared.Global)
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local InputManager = require(controller.InputManager)
local BaseState = require(controller.SimStates.BaseState)
local FloorCheck = require(controller.Common.FloorCheck)

local STATE_ID = 0

-- General physics config
local MOVE_SPEED = 1.75
local DASH_SPEED = 30.2
local GND_CLEAR_DIST = 0.45 -- 0.2
local MAX_INCLINE = math.rad(70) -- radiants
local JUMP_HEIGHT = 6
local JUMP_DELAY = 0.28
local MOVE_DAMP = 0.4 -- lower value ~ more rigid movement
local MOVE_DT = 0.05 -- time delta for move accel

local FORCE_STEPUP = false -- whether the player will be forced up steep inclines, if too low to the ground
local GND_FORCE_DIST = 0.1 -- height at which player will be forced up, if FORCE_STEUP is true

local DO_QUAKE_JUMP_SOUND = true -- To be removed later

-- Animation
local ANIM_THRESHHOLD = 0.1 -- Studs/s
local ANIM_SPEED_FAC = 0.06

local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X
local COLL_HEIGHT = CharacterDef.PARAMS.MAINCOLL_SIZE.X
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)
local PI2 = math.pi*2

-- Ground ray parameters
local ray_params_gnd = RaycastParams.new()
ray_params_gnd.CollisionGroup = Global.COLL_GROUPS.PLAYER
ray_params_gnd.FilterType = Enum.RaycastFilterType.Exclude
ray_params_gnd.IgnoreWater = true
ray_params_gnd.RespectCanCollide = true

-- Create required physics
local function createForces(mdl: Model): {[string]: Instance}
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
    posForce.MaxVelocity = 100000
    posForce.Responsiveness = 200
    posForce.ForceRelativeTo = Enum.ActuatorRelativeTo.World
    posForce.Position = mdl.PrimaryPart.CFrame.Position

    return {
        moveForce = moveForce,
        rotForce = rotForce,
        posForce = posForce,
    } :: {AlignPosition | AlignOrientation | VectorForce}
end

local function getCFrameRelMoveVec(camCFrame: CFrame, relativeVec: Vector3): Vector3
    return CFrame.new(
        VEC3_ZERO,
        Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        ).Unit
    ):VectorToWorldSpace(relativeVec)
end

local function projectOnPlaneVec3(v: Vector3, norm: Vector3)
    local sqrMag = norm:Dot(norm)
    if (sqrMag < 0.01) then
        return v
    end
    local dot = v:Dot(norm)
    return Vector3.new(
        v.X - norm.X * dot / sqrMag,
        v.Y - norm.Y * dot / sqrMag,
        v.Z - norm.Z * dot / sqrMag
    )
end

-- local function angleAbs(angle: number): number
-- 	while angle < 0 do
-- 		angle += PI2
-- 	end
-- 	while angle > PI2 do
-- 		angle  -= PI2
-- 	end
-- 	return angle
-- end

-- local function angleShortest(a0: number, a1: number): number
-- 	local d1 = angleAbs(a1 - a0)
-- 	local d2 = -angleAbs(a0 - a1)
-- 	return math.abs(d1) > math.abs(d2) and d2 or d1
-- end

-- local function lerpAngle(a0: number, a1: number, t: number): number
-- 	return a0 + angleShortest(a0, a1)*t
-- end


------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local Ground = setmetatable({}, BaseState)
Ground.__index = Ground

function Ground.new(...)
    local self = setmetatable(BaseState.new(...) :: BaseState.BaseState, Ground)
    self.id = STATE_ID

    self.character = self._simulation.character :: Model
    self.forces = createForces(self.character)
    self.jumpSignal = false
    self.dashActive = false
    self.grounded = false
    self.inWater = false

    self.animation = self._simulation.animation

    ray_params_gnd.FilterDescendantsInstances = self.character:GetChildren()

    return self
end

function Ground:stateEnter()
    if (not self.forces) then
        return
    end
    for _, f in self.forces do
        f.Enabled = true
    end
    self.animation:setState("Idle")
end

function Ground:stateLeave()
    if (not self.forces) then
        return
    end
    for _, f in self.forces :: {AlignOrientation | AlignPosition | VectorForce} do
        f.Enabled = false
    end
end

local j_lastDown = false
local j_Delay = 0
local lastYPos = 0
local jumped = false

function Ground:updateJump(dt: number, overwrite: boolean?)
    -- Manages input cooldown for the jump action
    local function updateJumpTime()
        if (InputManager:getJumpKeyDown()) then
            if (not j_lastDown and j_Delay <= 0) then
                j_lastDown = true
                j_Delay = JUMP_DELAY
                self.jumpSignal = true
                return
            end
        else
            j_lastDown = false
        end

        j_Delay = math.max(j_Delay - dt, 0)
        self.jumpSignal = false
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
        if (self.jumpSignal or overwrite) then
            if (DO_QUAKE_JUMP_SOUND) then
                local s = Instance.new("Sound")
                s.SoundId = "rbxassetid://5466166437"
                SoundService:PlayLocalSound(s)
                s:Destroy()
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

-- Updates horizontal movement force
function Ground:updateMove(dt: number, normal: Vector3, normAngle: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame = Workspace.CurrentCamera.CFrame
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local mass = primaryPart.AssemblyMass
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)

    local accelVec, moveDirVec, target
    if (self.dashActive and not (normAngle > MAX_INCLINE)) then
        moveDirVec = -projectOnPlaneVec3(
            camCFrame.LookVector, VEC3_UP
        ).Unit
        target = currPos - moveDirVec * DASH_SPEED
        accelVec = 2 * ((target - currPos) - currHoriVel * MOVE_DT)/(MOVE_DT * MOVE_DT)
    else
        moveDirVec = getCFrameRelMoveVec(camCFrame, InputManager:getMoveVec())
        target = currPos - moveDirVec * MOVE_SPEED
        accelVec = 2 * ((target - currPos) - currHoriVel * MOVE_DT)/(MOVE_DT * MOVE_DAMP)
    end
    self.forces.moveForce.Force = accelVec * mass

    if (not self.grounded and not self.dashActive) then
        self.forces.moveForce.Force *= 0.1
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Ground update
------------------------------------------------------------------------------------------------------------------------
function Ground:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame = Workspace.CurrentCamera.CFrame
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)
    local g = Workspace.Gravity
    local mass = primaryPart.AssemblyMass

    -- Do physics checks
    local gndPhysData: FloorCheck.physData = FloorCheck(
        currPos, PHYS_RADIUS, HIP_HEIGHT, GND_CLEAR_DIST, ray_params_gnd
    )
    self.grounded = gndPhysData.grounded
    self.inWater = gndPhysData.inWater
    self.dashActive = GameClient:getIsDashing()

    -- State transitions
    if (self.inWater) then
        self._simulation:transitionState(self._simulation.states.Water)
    end

    if (self.grounded) then
        local targetPosY = gndPhysData.gndHeight + HIP_HEIGHT

        -- Scale force with cubed vertical velocity to compensate for high falls
        self.forces.posForce.MaxAxesForce = VEC3_UP * mass * (g * 20 + currVel.Y * currVel.Y)
        self.forces.posForce.Position = Vector3.new(0, targetPosY, 0)

        -- Force character to get more ground distance, if too close to ground
        if (FORCE_STEPUP) then
            local closestPosDiff = math.abs(gndPhysData.closestPos.Y - primaryPart.CFrame.Position.Y)

            if (closestPosDiff < GND_FORCE_DIST) then
                local isSteep = false

                -- Step-up only possible, if there is no low ceiling and no steep slope
                local upRay = Workspace:Raycast(
                    gndPhysData.closestPos, VEC3_UP * (HIP_HEIGHT + COLL_HEIGHT + 0.05), ray_params_gnd
                ) :: RaycastResult
                -- TODO: get normal from gndPhysData returned part directly
                local downRay = Workspace:Raycast(
                    gndPhysData.closestPos + VEC3_UP * 0.1, -VEC3_UP, ray_params_gnd
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
    else
        self.forces.posForce.Enabled = false
    end

    -- Update jumping
    self:updateJump(dt)

    -- Update dashing and movement
    self:updateMove(dt, gndPhysData.normal, gndPhysData.normalAngle)

    -- Update animation
    if (currHoriVel.Magnitude >= ANIM_THRESHHOLD) then
        self.animation:setState("Walk")
        self.animation:adjustSpeed(currHoriVel.Magnitude * ANIM_SPEED_FAC)
    else
        self.animation:setState("Idle")
        self.animation:adjustSpeed(1)
    end

    -- Update model rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        )
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO
end

function Ground:destroy()
    if (self.forces) then
        for i, force in pairs(self.forces) do
            (self.forces[i] :: Instance):Destroy()
        end
    end
    setmetatable(self, nil)
end

return Ground
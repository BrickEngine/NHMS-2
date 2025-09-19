local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local controller = script.Parent.Parent
local CollisionGroups = require(ReplicatedStorage.Shared.CollisionGroups)
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local InputManager = require(controller.InputManager)
local BaseState = require(controller.SimStates.BaseState)
local FloorCheck = require(controller.Common.FloorCheck)

local STATE_ID = 0

-- General physics config
local GND_MOVE_SPEED = 2.5
local GND_CLEAR_DIST = 0.2
local MAX_INCLINE = math.rad(70) -- degrees
local JUMP_HEIGHT = 6
local JUMP_TIME = 0.3
local DASH_TIME = 0.4
local MOVE_DAMP = 0.4 -- Lower value ~ more rigid movement
local PHYS_DT = 0.05 -- Time delta for walk acceleration

local FORCE_STEPUP = false -- Whether the player will be forced up steep inclines, if too low to the ground
local GND_FORCE_DIST = 0.4 -- Height at which player will be forced up, if FORCE_STEUP is true

local DO_QUAKE_JUMP_SOUND = true -- To be removed later

-- Animation
local ANIM_THRESHHOLD = 0.1 -- studs/s
local ANIM_SPEED_FAC = 0.06

local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X
local COLL_HEIGHT = CharacterDef.PARAMS.MAINCOLL_SIZE.X
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)
local PI2 = math.pi*2

-- Ground ray parameters
local ray_params_gnd = RaycastParams.new()
ray_params_gnd.CollisionGroup = CollisionGroups.PLAYER
ray_params_gnd.FilterType = Enum.RaycastFilterType.Exclude
ray_params_gnd.IgnoreWater = true
ray_params_gnd.RespectCanCollide = true

local function createForces(mdl: Model): {[string]: Instance}
    local att = Instance.new("Attachment")
    att.WorldAxis = Vector3.new(0, 1, 0)
    att.Name = "Ground"
    att.Parent = mdl.PrimaryPart

    local moveForce = Instance.new("VectorForce")
    moveForce.Enabled = false
    moveForce.Attachment0 = att
    moveForce.ApplyAtCenterOfMass = true
    moveForce.RelativeTo = Enum.ActuatorRelativeTo.World
    moveForce.Parent = mdl.PrimaryPart

    local rotForce = Instance.new("AlignOrientation")
    rotForce.Enabled = false
    rotForce.Attachment0 = att
    rotForce.Mode = Enum.OrientationAlignmentMode.OneAttachment
    rotForce.AlignType = Enum.AlignType.PrimaryAxisParallel
    rotForce.Responsiveness = 200
    rotForce.MaxTorque = math.huge
    rotForce.MaxAngularVelocity = math.huge
    rotForce.Parent = mdl.PrimaryPart
    rotForce.ReactionTorqueEnabled = true
    rotForce.PrimaryAxis = VEC3_UP

    local posForce = Instance.new("AlignPosition")
    posForce.Enabled = false
    posForce.Attachment0 = att
    posForce.Mode = Enum.PositionAlignmentMode.OneAttachment
    posForce.ForceLimitMode = Enum.ForceLimitMode.PerAxis
    posForce.MaxAxesForce = Vector3.zero
    posForce.MaxVelocity = 100000
    posForce.Responsiveness = 200
    posForce.ForceRelativeTo = Enum.ActuatorRelativeTo.World
    posForce.Position = mdl.PrimaryPart.CFrame.Position
    posForce.Parent = mdl.PrimaryPart

    return {
        moveForce = moveForce,
        rotForce = rotForce,
        posForce = posForce,
    }
end

local function getCFrameRelMoveVec(camCFrame: CFrame): Vector3
    return CFrame.new(
        VEC3_ZERO,
        Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        ).Unit
    ):VectorToWorldSpace(InputManager:getMoveVec())
end

local function makeCFrame(up, look)
	local upu = up.Unit
	local ru = upu:Cross((-look).Unit).Unit
	-- orthonormalize, keeping up vector
	local looku = -upu:Cross(ru).Unit
	return CFrame.new(
        0, 0, 0,
        ru.x, upu.x, looku.x,
        ru.y, upu.y, looku.y,
        ru.z, upu.z, looku.z
    )
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

local function calcWalkAccel(moveVec: Vector3, rootPos: Vector3, currVel: Vector3, normal: Vector3, dt: number): Vector3
    --local adjMoveVec = projectOnPlaneVec3(moveVec, normal)
    local target = rootPos - moveVec * GND_MOVE_SPEED
    return 2*((target - rootPos) - currVel*dt)/(dt*MOVE_DAMP)
end

local function angleAbs(angle: number): number
	while angle < 0 do
		angle += PI2
	end
	while angle > PI2 do
		angle  -= PI2
	end
	return angle
end

local function angleShortest(a0: number, a1: number): number
	local d1 = angleAbs(a1 - a0)
	local d2 = -angleAbs(a0 - a1)
	return math.abs(d1) > math.abs(d2) and d2 or d1
end

local function lerpAngle(a0: number, a1: number, t: number): number
	return a0 + angleShortest(a0, a1)*t
end

local jTime = 0
local jSignal = false

local function jumpSignal()
	if (InputManager:getIsJumping()) then
		if (not jSignal) then
			jSignal = true
			return true
		end
	else
		jSignal = false
	end
	return false
end

local function decCount(count: number, dt: number): number
    count -= dt
    if (count < 0) then count = 0 end
    return count
end

---------------------------------------------------------------------------------------

local Ground = setmetatable({}, BaseState)
Ground.__index = Ground

function Ground.new(...)
    local self = setmetatable(BaseState.new(...) :: BaseState.BaseStateType, Ground) :: any

    self.id = STATE_ID

    self.character = self._simulation.character :: Model
    self.forces = createForces(self.character)
    self.jumpSignal = false
    self.dashSignal = false
    self.inDash = false

    self.animation = self._simulation.animation

    ray_params_gnd.FilterDescendantsInstances = self.character:GetChildren()

    return self
end

function Ground:stateEnter()
    if (not self.forces) then
        return
    end
    for _, f: Instance in self.forces do
        f.Enabled = true
    end
    self.animation:setState("Idle")
end

function Ground:stateLeave()
    if (not self.forces) then
        return
    end
    for _, f: Instance in self.forces do
        f.Enabled = false
    end
end

local jump_lastDown = false
local jump_time = 0
local dashDirVec = VEC3_ZERO

function Ground:updateJump(dt: number)
    if (InputManager:getIsJumping()) then
		if (not jump_lastDown and jTime <= 0) then
			jump_lastDown = true
            jump_time = JUMP_TIME
			self.jumpSignal = true
            return
		end
	else
		jump_lastDown = false
	end

    jump_time -= dt
    if (jump_time < 0) then
        jump_time = 0
    end

	self.jumpSignal = false
end

local dash_lastDown = false
local dash_time = 0

function Ground:updateDash(dt: number)
    if (InputManager:getIsDashing()) then
		if (not dash_lastDown and jTime <= 0) then
			dash_lastDown = true
            dash_time = DASH_TIME
			self.dashSignal = true
            return
		end
	else
		dash_lastDown = false
	end

    dash_time -= dt
    if (dash_time < 0) then
        dash_time = 0
    end

	self.dashSignal = false
end

---------------------------------------------------------------------------------------
-- Ground update
---------------------------------------------------------------------------------------

local lastYPos = 0
local jumped = false

function Ground:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame = Workspace.CurrentCamera.CFrame
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local g = Workspace.Gravity
    local mass = primaryPart.AssemblyMass

    -- Do physics checks
    local gndPhysData: FloorCheck.physData = FloorCheck(
        currPos, PHYS_RADIUS, HIP_HEIGHT, GND_CLEAR_DIST, ray_params_gnd
    )

    ---------------------------------------------------------------------------------------
    -- State transitions

    if (gndPhysData.inWater) then
        self._simulation:transitionState(self._simulation.states.Water)
    end

    ---------------------------------------------------------------------------------------

    self:updateJump(dt)
    self:updateDash(dt)

    local moveDirVec = getCFrameRelMoveVec(camCFrame)
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)
    local accelVec = calcWalkAccel(
        moveDirVec, currPos, currHoriVel, gndPhysData.normal, PHYS_DT
    )

    -- Update animation
    if (currHoriVel.Magnitude >= ANIM_THRESHHOLD) then
        self.animation:setState("Walk")
        self.animation:adjustSpeed(currHoriVel.Magnitude * ANIM_SPEED_FAC)
    else
        self.animation:setState("Idle")
        self.animation:adjustSpeed(1)
    end

    if (gndPhysData.grounded) then
        local targetPosY = gndPhysData.gndHeight + HIP_HEIGHT
        local onSteepIncline = false

        self.forces.posForce.Position = Vector3.new(0, targetPosY, 0)
        self.forces.posForce.MaxAxesForce = VEC3_UP * g * mass * 20

        if (gndPhysData.normalAngle > MAX_INCLINE) then
            self.forces.moveForce.Force = projectOnPlaneVec3(accelVec * 0.1, gndPhysData.normal) * mass
            self.forces.posForce.Enabled = false
            onSteepIncline = true
        else
            self.forces.moveForce.Force = accelVec * mass
        end

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
                    print(math.deg(incAng))
                    isSteep = incAng > MAX_INCLINE
                end
                if (not (isSteep or upRay)) then
                    local newPosOffset = VEC3_UP * (closestPosDiff + HIP_HEIGHT)

                    primaryPart.CFrame *= CFrame.new(newPosOffset)
                    self.forces.posForce.Position = newPosOffset
                end
            end
        end

        -- Handle jumping
        if (not onSteepIncline) then
            if (jump_time <= 0 or (jumped and currPos.Y < lastYPos)) then
                self.forces.posForce.Enabled = true
                jumped = false
            end

            if (self.jumpSignal) then
                if (DO_QUAKE_JUMP_SOUND) then
                    local s = Instance.new("Sound")
                    s.SoundId = "rbxassetid://5466166437"
                    SoundService:PlayLocalSound(s)
                    s:Destroy()
                end

                self.forces.posForce.Enabled = false

                local jumpInitVel: number = math.sqrt(Workspace.Gravity * 2 * JUMP_HEIGHT)
                primaryPart:ApplyImpulse(VEC3_UP * (jumpInitVel - currVel.Y) * mass)
                jumped = true
            end
        end
    else
        self.forces.moveForce.Force = accelVec * mass * 0.1
        self.forces.posForce.Enabled = false
    end

    -- Handle dashing
    local vertMoveVec = Vector3.new(0, primaryPart.AssemblyLinearVelocity.Y, 0)
    if (self.dashSignal) then
        dashDirVec = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z)
        primaryPart:ApplyImpulse((-primaryPart.AssemblyLinearVelocity + dashDirVec * 100) * mass)
        --primaryPart:ApplyImpulse(dashDirVec * mass)
        self.inDash = true
    end
    if (not InputManager:getIsDashing()) then
        self.inDash = false
    end

    if (self.inDash) then
        self.forces.moveForce.Force = accelVec * mass * 0.02
        dashDirVec = Vector3.new(camCFrame.LookVector.X, vertMoveVec, camCFrame.LookVector.Z)
        primaryPart:ApplyImpulse((-primaryPart.AssemblyLinearVelocity + dashDirVec * 100) * mass)
    end

    -- Align primary part orientation
    if (self.inDash) then
        primaryPart.CFrame = CFrame.lookAlong(
            primaryPart.CFrame.Position, Vector3.new(
                primaryPart.AssemblyLinearVelocity.X, 0 , primaryPart.AssemblyLinearVelocity.Z
            )
        )
    else
        primaryPart.CFrame = CFrame.lookAlong(
            primaryPart.CFrame.Position, Vector3.new(
                camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
            )
        )
    end
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO

    lastYPos = currPos.Y
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
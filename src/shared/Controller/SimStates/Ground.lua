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

-- physics
local GND_MOVE_SPEED = 2.5
local GND_CLEAR_DIST = 0.2
local MAX_INCLINE = math.rad(70)    -- degrees
local JUMP_HEIGHT = 6
local JUMP_TIME = 0.3
local MOVE_DAMP = 0.4               -- Lower value ~ more rigid movement
local PHYS_DT = 0.05                -- Time delta for walk acceleration

local GND_MIN_DIST = 0.5
local FORCE_STEPUP = false          -- Whether the player will be forced up steep inclines, if too low to the ground

-- animation speeds / threshold
local ANIM_THRESHHOLD = 0.1 -- studs/s
local ANIM_SPEED_FAC = 0.3

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

local jTime = 0
local jSignal = false

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

local function decrementCounter(count: number, dt: number): number
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

local lastTargetAng = 0
local lastYPos = 0
local jumped = false

---------------------------------------------------------------------------------------
-- Ground update
---------------------------------------------------------------------------------------

function Ground:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame: CFrame = Workspace.CurrentCamera.CFrame
    local currVel: Vector3 = primaryPart.AssemblyLinearVelocity
    local currPos: Vector3 = primaryPart.CFrame.Position
    local g = Workspace.Gravity
    local mass: number = primaryPart.AssemblyMass
    local movingUp: boolean = currVel.Y > 0.1

    -- Do physics checks
    local physData: FloorCheck.physData = FloorCheck(
        currPos, PHYS_RADIUS, HIP_HEIGHT, GND_CLEAR_DIST, ray_params_gnd
    )

    if (physData.inWater) then
        self._simulation:transitionState(self._simulation.states.Water)
    end

    local moveDirVec = getCFrameRelMoveVec(camCFrame)
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)
    local accelVec = calcWalkAccel(
        moveDirVec, currPos, currHoriVel, physData.normal, PHYS_DT
    )

    -- Align primary part orientation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        )
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO


    -- Update animation
    if (currHoriVel.Magnitude >= ANIM_THRESHHOLD) then
        self.animation:setState("Walk")
        self.animation:adjustSpeed(currHoriVel.Magnitude * ANIM_SPEED_FAC)
    else
        self.animation:setState("Idle")
        self.animation:adjustSpeed(1)
    end

    if (physData.grounded) then
        local targetPosY = physData.gndHeight + HIP_HEIGHT
        local onIncline = false

        self.forces.posForce.Position = Vector3.new(0, targetPosY, 0)
        self.forces.posForce.MaxAxesForce = VEC3_UP * g * mass * 20

        if (physData.normalAngle > MAX_INCLINE) then
            self.forces.moveForce.Force = projectOnPlaneVec3(accelVec * 0.1, physData.normal) * mass
            self.forces.posForce.Enabled = false
            onIncline = true
        else
            self.forces.moveForce.Force = accelVec * mass
        end

        if (math.abs(primaryPart.CFrame.Position.Y - physData.closestPos.Y) < GND_MIN_DIST) then
            local newPosOffset = VEC3_UP * (physData.closestPos.Y - primaryPart.CFrame.Position.Y + HIP_HEIGHT)
            print(physData.closestPos.Y)
            
            primaryPart.CFrame *= CFrame.new(newPosOffset)
            self.forces.posForce.Position = newPosOffset
            -- self.forces.posForce.Position = Vector3.new(
            --     0, primaryPart.CFrame.Position.Y + GND_MIN_DIST * 20, 0
            -- )

        end

        -- handle jumping
        if (not onIncline) then
            if (jTime <= 0 or (jumped and currPos.Y < lastYPos)) then
                self.forces.posForce.Enabled = true
                jumped = false
            end

            if (jumpSignal() and jTime <= 0) then
                -- temp sound for fun
                do
                    local s = Instance.new("Sound")
                    s.SoundId = "rbxassetid://5466166437"
                    SoundService:PlayLocalSound(s)
                    s:Destroy()
                end

                self.forces.posForce.Enabled = false

                local jumpInitVel: number = math.sqrt(Workspace.Gravity * 2 * JUMP_HEIGHT)
                primaryPart:ApplyImpulse(VEC3_UP * (jumpInitVel - currVel.Y) * mass)
                jTime = JUMP_TIME
                jumped = true
            end
        end
    else
        self.forces.moveForce.Force = accelVec * mass * 0.1
        self.forces.posForce.Enabled = false
    end

    jTime = decrementCounter(jTime, dt)
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
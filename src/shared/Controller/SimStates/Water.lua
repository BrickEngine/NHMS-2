--[[
    State machine submodule.
    Logic for wall-running movement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local controller = script.Parent.Parent
local BaseState = require(controller.SimStates.BaseState)
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local AnimationStateId = require(ReplicatedStorage.Shared.Enums.AnimationStateId)
local InputManager = require(controller.InputManager)
local SoundManager = require(ReplicatedStorage.Shared.SoundManager)
local PhysCheck = require(controller.Common.PhysCheck)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

local STATE_ID = 1

-- physics
local SWIM_SPEED = 1.75
local SWIM_DAMP = 0.45
local PHYS_DT = 0.05
local BUOY_FORCE_FAC = 0.765 -- scales compensated buoyancy force
local INP_READ_DELAY = 0.15 -- by how many seconds to delay vertical swim input after entering the state
local DIVE_CONE_ANG_LIM = math.rad(45) -- rad - angle limit for remapping swim direction when diving

local GND_CLEAR_DIST = 0.425 -- should be smaller than the one in the ground state
local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local COMP_HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X * 0.9

-- animation
local SWIM_ANIM_SPEED_FAC = 0.1

-- constants
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)
local EPSILON = 0.001

------------------------------------------------------------------------------------------------------------------------
-- Local vars

local canSwimUp = false

-- Create required physics constraints
local function createForces(mdl: Model): {[string]: Instance}
    assert(mdl.PrimaryPart)

    local att = Instance.new("Attachment")
    att.WorldAxis = Vector3.new(0, 1, 0)
    att.Name = "Water"
    att.Parent = mdl.PrimaryPart

    local moveForce = Instance.new("VectorForce", mdl.PrimaryPart)
    moveForce.Name = "WaterVecForce"
    moveForce.Enabled = false
    moveForce.Attachment0 = att
    moveForce.ApplyAtCenterOfMass = true
    moveForce.RelativeTo = Enum.ActuatorRelativeTo.World
    moveForce.Visible = true

    local posForce = Instance.new("AlignPosition", mdl.PrimaryPart)
    posForce.Name = "WaterPosForce"
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
        posForce = posForce,
    } :: {[string]: Instance}
end

local function getCamRelInpVec(camCFrame: CFrame, relVec: Vector3): Vector3
    local camFwdVec = camCFrame.LookVector
    local camRightVec = camCFrame.RightVector

    local transRelVec = camFwdVec * (-relVec.Z) + camRightVec * relVec.X
    if (transRelVec.Magnitude < EPSILON) then
        return VEC3_ZERO
    else 
        return transRelVec.Unit
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local Water = setmetatable({}, BaseState)
Water.__index = Water

function Water.new(...)
    local self = BaseState.new(...) :: BaseState.BaseState

    self.id = STATE_ID

    self.shared = self._simulation.stateShared
    self.character = self._simulation.character :: Model
    self.forces = createForces(self.character)
    self.animation = self._simulation.animation

    --self.mainColl = (self.character :: Model):FindFirstChild(CharacterDef.PARAMS.MAINCOLL_NAME) :: BasePart
    --self.mainCollBuoySensor = createBuoySensForPart(self.mainColl) :: BuoyancySensor

    return setmetatable(self, Water)
end

function Water:stateEnter(stateId: number, params: any?)
    if (not self.forces) then
        warn("No forces to enable in state: 'Water'"); return
    end

    canSwimUp = false
    self.forces.moveForce.Enabled = true
    -- TODO: swim animation
    self.animation:setState(AnimationStateId.WALK)

    SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.WATER_SPLASH, true)
end

function Water:stateLeave()
    self.shared.inWater = false
    self.shared.underWater = false
    self.shared.onWaterSurface = false

    if (not self.forces) then
        return
    end
    for _, f in self.forces do
        f.Enabled = false
    end
end


-- Updates camera directed movement force
function Water:updateSwim(dt: number, rawInpDir: Vector3)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camera = Workspace.CurrentCamera
    local camDir = camera.CFrame.LookVector
    local camHoriDir = Vector3.new(camDir.X, 0, camDir.Z)
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local mass = primaryPart.AssemblyMass
    local gravity = Workspace.Gravity
    local onSurface = self.shared.onWaterSurface

    local swimDirVec = getCamRelInpVec(camera.CFrame, rawInpDir)
    local planeSwimDirVecXZ = MathUtil.projectOnPlaneVec3(swimDirVec, VEC3_UP)
    local camFacingDown = camera.CFrame.LookVector:Dot(VEC3_UP) < 0
    local movingDown = swimDirVec.Unit:Dot(VEC3_UP) > 0
    local diving = camFacingDown and onSurface
    
    local corrSwimDirVec = swimDirVec
    if (diving and rawInpDir.Z > EPSILON) then
        corrSwimDirVec = MathUtil.compressVectorInCone(
            swimDirVec, 
            primaryPart.CFrame.LookVector * rawInpDir.Z, 
            DIVE_CONE_ANG_LIM
        )
    end
    if (not (canSwimUp or movingDown)) then --or cantSwimUpCond
        corrSwimDirVec = planeSwimDirVecXZ
    end

    -- if near a ledge, add a little vertical force
    local nearLedge = false
    if (planeSwimDirVecXZ.Magnitude > EPSILON) then
        nearLedge = PhysCheck.checkLedge(currPos, -planeSwimDirVecXZ * 2, PHYS_RADIUS)
    end
    if (nearLedge) then
        corrSwimDirVec += -gravity * VEC3_UP * 0.02
    end

    -- calc target force
    local target = currPos - corrSwimDirVec * SWIM_SPEED
    local accelVec = 2 * ((target - currPos) - currVel * PHYS_DT)/(PHYS_DT * SWIM_DAMP)

    -- compensate for world gravity / bouyant force
    local unitBuoyForce = VEC3_UP * gravity * BUOY_FORCE_FAC
    if (not canSwimUp) then
        unitBuoyForce = VEC3_ZERO
    end
    self.forces.moveForce.Force = (accelVec + unitBuoyForce) * mass

    -- update playermodel rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, camHoriDir
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO
end

local diveSignal = false
local lastOnSurface = false
local uwTime = 0

-- TODO: move sound logic over time GameClient
function Water:updateSounds(dt: number)
    local inWater: boolean = self.shared.inWater
    local onSurface: boolean = self.shared.onWaterSurface 

    if (not inWater) then
        return
    end

    if (lastOnSurface ~= onSurface) then
        diveSignal = true
    else
        diveSignal = false
    end
    lastOnSurface = onSurface

    if (diveSignal and not onSurface) then
        SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.WATER_DIVE, true)
    elseif (diveSignal and onSurface) then
        if (uwTime > 2) then 
            SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.WATER_SURFACE, true)
        end
    end

    if (onSurface) then
        uwTime = 0
    else
        uwTime += dt
    end

end

------------------------------------------------------------------------------------------------------------------------
-- Water update
------------------------------------------------------------------------------------------------------------------------

function Water:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local inpVec = InputManager:getMoveVec()
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position

    -- phys checks
    local buoySensor = self.shared.buoySensor
    local waterData: PhysCheck.waterData = PhysCheck.checkWater(
        currPos, PHYS_RADIUS, buoySensor
    )
    local groundData: PhysCheck.groundData = PhysCheck.checkFloor(
        currPos, PHYS_RADIUS, COMP_HIP_HEIGHT, GND_CLEAR_DIST
    )

    self.shared.grounded = groundData.grounded
    self.shared.inWater = waterData.inWater
    self.shared.underWater = waterData.fullSubmerged
    self.shared.onWaterSurface = waterData.onSurface

    -- movement update
    canSwimUp = self.shared.stateTime > INP_READ_DELAY
    self:updateSwim(dt, inpVec)
    self:updateSounds(dt)

    -- animation
    self.animation:adjustSpeed(currVel.Magnitude * SWIM_ANIM_SPEED_FAC)

    -- state transitions
    local groundConditions = self.shared.grounded and self.shared.onWaterSurface
    if (not self.shared.inWater or groundConditions) then
        self._simulation:transitionState(PlayerStateId.GROUND); return
    end
end

function Water:destroy()

end

return Water
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

local STATE_ID = 1

-- physics
local SWIM_SPEED = 1.75
local SWIM_DAMP = 0.45
local PHYS_DT = 0.05
local BUOY_FORCE_FAC = 0.765 -- scales compensated buoyancy force

-- animation
local SWIM_ANIM_SPEED_FAC = 0.1

-- constants
local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)

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

local function createBuoySensForPart(part: BasePart): BuoyancySensor
    local buoySens = Instance.new("BuoyancySensor", part)
    buoySens.UpdateType = Enum.SensorUpdateType.OnRead

    return buoySens
end

local function getCamRelInpVec(camCFrame: CFrame, relVec: Vector3): Vector3
    local camFwdVec = camCFrame.LookVector
    local camRightVec = camCFrame.RightVector

    local transRelVec = camFwdVec * (-relVec.Z) + camRightVec * relVec.X
    if (transRelVec.Magnitude < 0.01) then
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

    self.mainColl = (self.character :: Model):FindFirstChild(CharacterDef.PARAMS.MAINCOLL_NAME) :: BasePart
    --self.mainCollBuoySensor = createBuoySensForPart(self.mainColl) :: BuoyancySensor

    return setmetatable(self, Water)
end

function Water:stateEnter(stateId: number, params: any?)
    if (not self.forces) then
        warn("No forces to enable in state: 'Water'"); return
    end

    self.forces.moveForce.Enabled = true
    -- TODO: swim animation
    self.animation:setState(AnimationStateId.WALK)

    SoundManager:updateGlobalSound(SoundManager.SOUND_ITEMS.WATER_SPLASH, true)
end

function Water:stateLeave()
    self.shared.inWater = false
    self.shared.underWater = false

    if (not self.forces) then
        return
    end
    for _, f in self.forces do
        f.Enabled = false
    end
end


-- Updates horizontal movement force
function Water:updateSwim(dt: number, rawInpDir: Vector3, gravity: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camera = Workspace.CurrentCamera
    local camDir = camera.CFrame.LookVector
    local camHoriDir = Vector3.new(camDir.X, 0, camDir.Z)
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local mass = primaryPart.AssemblyMass

    local swimDirVec = getCamRelInpVec(camera.CFrame, rawInpDir)
    local target = currPos - swimDirVec * SWIM_SPEED
    local accelVec = 2 * ((target - currPos) - currVel * PHYS_DT)/(PHYS_DT * SWIM_DAMP)

    -- compensate for world gravity / bouyant force
    local unitBuoyForce = VEC3_UP * gravity * BUOY_FORCE_FAC
    self.forces.moveForce.Force = (accelVec + unitBuoyForce) * mass

    -- update playermodel rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, camHoriDir
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO
end

------------------------------------------------------------------------------------------------------------------------
-- Water update
------------------------------------------------------------------------------------------------------------------------

function Water:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local inpVec = InputManager:getMoveVec()
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local grav = Workspace.Gravity

    local buoySensor = self.shared.buoySensor
    local waterData: PhysCheck.waterData = PhysCheck.checkWater(
        currPos, PHYS_RADIUS, buoySensor
    )

    self.shared.inWater = waterData.inWater

    --local mainCollbuoySensor: BuoyancySensor = self.mainCollBuoySensor
    self.shared.underWater = waterData.fullSubmerged

    -- movement update
    self:updateSwim(dt, inpVec, grav)

    -- animation
    self.animation:adjustSpeed(currVel.Magnitude * SWIM_ANIM_SPEED_FAC)

    -- state transitions
    if (not self.shared.inWater) then
        self._simulation:transitionState(PlayerStateId.GROUND); return
    end 
end

function Water:destroy()

end

return Water
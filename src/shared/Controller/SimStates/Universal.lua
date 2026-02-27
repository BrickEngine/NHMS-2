--[[
    Universal state machine module that is always running when
    Simulation is initialized.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local controller = script.Parent.Parent
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local BaseState = require(controller.SimStates.BaseState)

local STATE_ID = PlayerStateId.NONE
local VEC3_UP = Vector3.new(0, 1, 0)

-- Creates a rotation force for keeping the character upright at all times
local function createRotForce(mdl: Model): AlignOrientation
    assert(mdl.PrimaryPart)

    local att = Instance.new("Attachment")
    att.WorldAxis = VEC3_UP
    att.Name = "Universal"
    att.Parent = mdl.PrimaryPart

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

    return rotForce
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Universal = setmetatable({}, BaseState)
Universal.__index = Universal

function Universal.new(...)
    local self = BaseState.new(...) :: BaseState.BaseState

    self.id = STATE_ID

    self.shared = self._simulation.stateShared
    self.character = self._simulation.character :: Model
    self.rotForce = createRotForce(self.character)

    return setmetatable(self, Universal)
end

function Universal:stateEnter(stateId: number, params: any?)
    self.rotForce.Enabled = true
end

function Universal:stateLeave()
    self.rotForce.Enabled = false
end

------------------------------------------------------------------------------------------------------------------------
-- Update
------------------------------------------------------------------------------------------------------------------------
function Universal:update(dt: number)
end

-- clean up created BuoyancySensor
function Universal:destroy()
    if (self.shared.buoySensor) then
        (self.shared.buoySensor :: BuoyancySensor):Destroy()
    end
    setmetatable(self, nil)
end

return Universal
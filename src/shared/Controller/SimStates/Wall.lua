--[[
    State machine submodule.
    Logic for wall-running movement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local controller = script.Parent.Parent
local GameClient = require(ReplicatedStorage.Shared.GameClient)
local Global = require(ReplicatedStorage.Shared.Global)
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local InputManager = require(controller.InputManager)
local BaseState = require(script.Parent.BaseState)
local PhysCheck = require(controller.Common.PhysCheck)

local STATE_ID = 2

local PHYS_RADIUS = CharacterDef.PARAMS.LEGCOLL_SIZE.Z * 0.5
local HIP_HEIGHT = CharacterDef.PARAMS.LEGCOLL_SIZE.X
local COLL_HEIGHT = CharacterDef.PARAMS.MAINCOLL_SIZE.X
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1, 0)

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

function Wall:stateEnter()
    return
end

function Wall:stateLeave()
    return
end

function Wall:update(dt: number)
    local primaryPart: BasePart = self.character.PrimaryPart
    local camCFrame = Workspace.CurrentCamera.CFrame
    local currVel = primaryPart.AssemblyLinearVelocity
    local currPos = primaryPart.CFrame.Position
    local currHoriVel = Vector3.new(currVel.X, 0, currVel.Z)
    local g = Workspace.Gravity
    local mass = primaryPart.AssemblyMass

    -- Update playermodel rotation
    primaryPart.CFrame = CFrame.lookAlong(
        primaryPart.CFrame.Position, Vector3.new(
            camCFrame.LookVector.X, 0, camCFrame.LookVector.Z
        )
    )
    primaryPart.AssemblyAngularVelocity = VEC3_ZERO
end

function Wall:destroy()

end

return Wall
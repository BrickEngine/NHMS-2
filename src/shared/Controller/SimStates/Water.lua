-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local Workspace = game:GetService("Workspace")


local controller = script.Parent.Parent
local BaseState = require(controller.SimStates.BaseState)
-- local Global = require(ReplicatedStorage.Shared.Global)
-- local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
-- local InputManager = require(controller.InputManager)
-- local PhysCheck = require(controller.Common.PhysCheck)

local STATE_ID = 1

-- physics
--local WATER_SURFACE_OFFS = 0.025

-- animation speeds / threshold
--local ANIM_SPEED_FAC_SWIM = 1

---------------------------------------------------------------------------------------

local Water = setmetatable({}, BaseState)
Water.__index = Water

function Water.new(...)
    local self = BaseState.new(...) :: BaseState.BaseState

    self.id = STATE_ID

    return setmetatable(self, Water)
end

function Water:stateEnter()

end

function Water:stateLeave()
    
end

function Water:update(dt: number)
    
end

function Water:destroy()

end

return Water
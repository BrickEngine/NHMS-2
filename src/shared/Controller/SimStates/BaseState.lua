--!strict

-- Abstract class for defining a simulation controlled state

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)

local BaseState = {}
BaseState.__index = BaseState

export type BaseState = typeof(setmetatable({}, BaseState))

function BaseState.new(_simulation)
    local self = setmetatable({}, BaseState)

    self._simulation = _simulation
    self.id = PlayerStateId.NONE

    return self
end

--[[
    Enters a state with the arg:
    @param stateId - state id that was transitioned from
    @param params - relevant additional data
]]
function BaseState:stateEnter(stateId: typeof(PlayerStateId.NONE), params: any?)
end

function BaseState:stateLeave()
end

function BaseState:stun(impulse: Vector3)
end

function BaseState:update(dt: number)
    error("cannot call update of abstract BaseState", 2)
end
 
function BaseState:destroy()
    error("cannot call destroy of abstract BaseState", 2)
end

return BaseState
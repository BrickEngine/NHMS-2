--!strict

-- Abstract class for defining a simulation controlled state

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerState = require(ReplicatedStorage.Shared.Enums.PlayerState)

local BaseState = {}
BaseState.__index = BaseState

export type BaseState = typeof(setmetatable({}, BaseState))

function BaseState.new(_simulation)
    local self = setmetatable({}, BaseState)

    self._simulation = _simulation
    self.id = PlayerState.NONE

    self.grounded = false
    self.inWater = false
    self.isDashing = false
    self.nearWall = false
    self.isRightSideWall = false
    self.wallTime = 0

    return self
end

function BaseState:resetData()
    self.grounded = false
    self.inWater = false
    self.isDashing = false
    self.nearWall = false
    self.isRightSideWall = false
    self.wallTime = 0
end

function BaseState:stateEnter(params: any?)
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
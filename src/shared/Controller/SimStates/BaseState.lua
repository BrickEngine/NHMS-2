--!strict

-- Abstract class for defining a simulation controlled state

-- export type BaseState = {
--     new: (_simulation: any) -> BaseState,
--     stateLeave: (BaseState) -> (),
--     stateEnter: (BaseState) -> (),
--     damagePlayer: (BaseState) -> (),
--     update: (BaseState, dt: number) -> (),
--     destroy: (BaseState) -> (),

--     _simulation: any,
--     id: number,

--     [string]: any
-- }

local BaseState = {}
BaseState.__index = BaseState

export type BaseState = typeof(setmetatable({}, BaseState))

function BaseState.new(_simulation)
    local self = setmetatable({}, BaseState)

    self._simulation = _simulation
    self.id = -1

    return self
end

function BaseState:stateEnter()
    return false
end

function BaseState:stateLeave()
    return false
end

function BaseState:damagePlayer(p: Player)
    print(p)
end

function BaseState:update(dt: number)
    error("cannot call update of abstract BaseState", 2)
end

function BaseState:destroy()
    error("cannot call destroy of abstract BaseState", 2)
end

return BaseState
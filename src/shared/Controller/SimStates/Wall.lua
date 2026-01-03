local controller = script.Parent.Parent
local BaseState = require(script.Parent.BaseState)
local PhysCheck = require(controller.Common.PhysCheck)

local STATE_ID = 2

local Wall = setmetatable({}, BaseState)
Wall.__index = Wall

function Wall.new(...)
    local self = setmetatable(BaseState.new(...) :: BaseState.BaseState, Wall)

    self.id = STATE_ID

    return self :: BaseState.BaseState
end

function Wall:stateEnter()
    return
end

function Wall:stateLeave()
    return
end

function Wall:update(dt: number)
    
end

function Wall:destroy()

end

return Wall
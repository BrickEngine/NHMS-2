local BaseState = require(script.Parent.BaseState)

local Air = setmetatable({}, BaseState)
Air.__index = Air

function Air.new(...)
    local self = setmetatable(BaseState.new(...) :: BaseState.BaseState, Air)

    return self :: BaseState.BaseState
end

function Air:stateEnter()
    return
end

function Air:stateLeave()
    return
end

function Air:update(dt: number)
    
end

function Air:destroy()

end

return Air
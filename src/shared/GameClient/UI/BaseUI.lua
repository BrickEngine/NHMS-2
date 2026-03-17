--!strict

-- Abstract base UI class

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIType = require(ReplicatedStorage.Shared.Enums.UIType)

local BaseUI = {}
BaseUI.__index = BaseUI

export type BaseUI = typeof(setmetatable({}, BaseUI))

function BaseUI.new()
    local self = setmetatable({}, BaseUI)

    self.type = UIType.NONE
    self.enabled = false

    return self
end

function BaseUI:enable(enable: boolean)
    error("cannot call enable of abstract BaseUI", 2)
end

function BaseUI:reset()
    error("cannot call reset of abstract BaseUI", 2)
end

function BaseUI:update(dt: number)
    error("cannot call update of abstract BaseUI", 2)
end
 
function BaseUI:destroy()
    error("cannot call destroy of abstract BaseUI", 2)
end

return BaseUI
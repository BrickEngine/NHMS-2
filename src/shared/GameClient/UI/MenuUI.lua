local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseUI = require(script.Parent.BaseUI)
local UIType = require(ReplicatedStorage.Shared.Enums.UIType)

local MenuUI = {}
MenuUI.__index = MenuUI

function MenuUI.init()
    local self = BaseUI.new() :: BaseUI.BaseUI

    self.type = UIType.MENU

    return setmetatable(self, MenuUI)
end

function MenuUI:enable(enable: boolean)
end

function MenuUI:reset()
end

function MenuUI:update(dt: number)
end
 
function MenuUI:destroy()
end

return MenuUI
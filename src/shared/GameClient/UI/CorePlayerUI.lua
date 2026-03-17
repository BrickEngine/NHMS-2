local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local UIType = require(ReplicatedStorage.Shared.Enums.UIType)
local BaseUI = require(script.Parent.BaseUI)
local GameUI = require(script.Parent.GameUI)
local MenuUI = require(script.Parent.MenuUI)

local UI_TYPE_MAP = {
    [UIType.NONE] = BaseUI,
    [UIType.GAME] = GameUI,
    [UIType.MENU] = MenuUI,
}

-- set all GUIs to be disabled at the start
local function disableStartUIs()
    local plrGui = Players.LocalPlayer.PlayerGui
    local starterGuiInsts = StarterGui:GetChildren()
    local cloneGuisNamesArr = {}

    for _, inst: Instance in starterGuiInsts do
        if (inst:IsA("ScreenGui")) then
            cloneGuisNamesArr[#cloneGuisNamesArr + 1] = inst.Name
        end
    end

    -- wait for all screenGuis to be cloned into PlayerGui for the first time on game start
    Players.LocalPlayer.CharacterAdded:Wait()
    for _, name: string in pairs(cloneGuisNamesArr) do
        plrGui:WaitForChild(name)
    end

    local plrGuiInsts = plrGui:GetChildren()

    print(plrGuiInsts)
    for _, u: Instance in pairs(plrGuiInsts) do
        if (u:IsA("ScreenGui")) then
            if (u.Name == "Freecam") then
                continue
            end
            u.Enabled = false
        end
    end
end

local startUiThread = coroutine.create(disableStartUIs)
coroutine.resume(startUiThread)

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local CorePlayerUI = {
    gameUI = nil,
    menuUI = nil,
    active = nil
}

function CorePlayerUI.init()
    CorePlayerUI.gameUI = GameUI.init()
    CorePlayerUI.menuUI = MenuUI.init()
end

function CorePlayerUI.setActive(uiType: string)
    if (CorePlayerUI.active) then
        CorePlayerUI.active:enable(false)
    end
    
    local newUI = UI_TYPE_MAP[uiType]
    newUI:enable(true)
    CorePlayerUI.active = newUI
end

return CorePlayerUI
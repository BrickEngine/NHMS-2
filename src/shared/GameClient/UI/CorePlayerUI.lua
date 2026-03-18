local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local UIType = require(ReplicatedStorage.Shared.Enums.UIType)
--local BaseUI = require(script.Parent.BaseUI)
local GameUI = require(script.Parent.GameUI)
local MenuUI = require(script.Parent.MenuUI)

-- set all GUIs to be disabled at the start
-- local function disableStartUIs()
--     local plrGui = Players.LocalPlayer.PlayerGui
--     local starterGuiInsts = StarterGui:GetChildren()
--     local cloneGuisNamesArr = {}

--     for _, inst: Instance in starterGuiInsts do
--         if (inst:IsA("ScreenGui")) then
--             cloneGuisNamesArr[#cloneGuisNamesArr + 1] = inst.Name
--         end
--     end

--     -- wait for all screenGuis to be cloned into PlayerGui for the first time on game start
--     Players.LocalPlayer.CharacterAdded:Wait()
--     for _, name: string in pairs(cloneGuisNamesArr) do
--         plrGui:WaitForChild(name)
--     end

--     local plrGuiInsts = plrGui:GetChildren()

--     for _, u: Instance in pairs(plrGuiInsts) do
--         if (u:IsA("ScreenGui")) then
--             if (u.Name == "Freecam") then
--                 continue
--             end
--             u.Enabled = false
--         end
--     end
-- end

-- local startUiThread = coroutine.create(disableStartUIs)
-- coroutine.resume(startUiThread)

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local CorePlayerUI = {
    gameUI = nil,
    menuUI = nil,
    currentActive = nil
}

function CorePlayerUI.init()
    CorePlayerUI.gameUI = GameUI.init()
    CorePlayerUI.menuUI = MenuUI.init()

    CorePlayerUI.map = {
        [UIType.NONE] = nil,
        [UIType.GAME] = CorePlayerUI.gameUI,
        [UIType.MENU] = CorePlayerUI.menuUI,
    }

    return CorePlayerUI
end

function CorePlayerUI.setActive(uiType: string)
    if (CorePlayerUI.currentActive) then
        CorePlayerUI.currentActive:enable(false)
    end
    
    local newUI = CorePlayerUI.map[uiType]
    CorePlayerUI.currentActive = newUI
    if (CorePlayerUI.currentActive) then
        CorePlayerUI.currentActive:enable(true)
    end
end

function CorePlayerUI.disableAll()
    CorePlayerUI.gameUI:enable(false)
    CorePlayerUI.menuUI:enable(false)
    CorePlayerUI.currentActive = nil
end

return CorePlayerUI.init()
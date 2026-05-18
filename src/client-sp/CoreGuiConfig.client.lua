-- disable default roblox GUIs

local StarterGui = game:GetService("StarterGui")

local function disableCoreGuis()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.AvatarSwitcher, false)
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.SelfView, false)
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end

disableCoreGuis()
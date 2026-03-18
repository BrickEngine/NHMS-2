local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local BaseUI = require(script.Parent.BaseUI)
local UIType = require(ReplicatedStorage.Shared.Enums.UIType)

local GAME_UI_NAME = "GameUI"

local playerGui = Players.LocalPlayer.PlayerGui
local starterGameGui = StarterGui:FindFirstChild(GAME_UI_NAME)
assert(starterGameGui, `No StarterGui object with name {GAME_UI_NAME} found`)

local guiUpdateConn = nil

local function onHealthChange(newHP: number)
	-- if (newHP < currentHP) then
	-- 	local dmg = currentHP - newHP
		
	-- 	if (newHP > 0) then
	-- 		local rand = math.random(1,4)
	-- 		DmgOverlay.Transparency 
	-- 			= 1 - math.clamp(dmg, DMG_OVERL_MIN, DMG_OVERL_MAX) * 0.01
	-- 		SoundService:PlayLocalSound(playSound(SND_HURT[rand]), 1.7)
	-- 	else
	-- 		DmgOverlay.Transparency = 1 - DMG_OVERL_MAX * 0.01
	-- 		SoundService:PlayLocalSound(playSound(SND_DEATH))
	-- 	end
	-- end
	-- currentHP = newHP
	-- Health.Text = tostring(newHP)
end

local function onKilled(Plr: Player, deathtime)
	-- if (Plr.UserId ~= Players.LocalPlayer.UserId) then
	-- 	return
	-- end
	-- HealthLbl.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	-- renderConn:Disconnect()
end

local function updateHPDisplay(dt: number)
	-- local currOverlayTransp = DmgOverlay.Transparency
	-- if (currOverlayTransp < 1) then
	-- 	currOverlayTransp += dt * DMG_OVERL_RATE
	-- else
	-- 	currOverlayTransp = 1
	-- end
	
	-- DmgOverlay.Transparency = currOverlayTransp
	-- HealthLbl.BackgroundColor3 
	-- 	= Color3.fromHSV(math.clamp(currentHP/300, 0, 1), 1, 1)
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local GameUI = {}
GameUI.__index = GameUI

function GameUI.init()
    local self = BaseUI.new() :: BaseUI.BaseUI

    self.type = UIType.GAME
    self.enabled = false
    self.loaded = false

    self.activeGuiObj = nil

    playerGui.ChildAdded:Connect(function(gui: Instance)
        if (gui:IsA("ScreenGui") and gui.Name == GAME_UI_NAME) then
            self.loaded = true
        end
    end)

    return setmetatable(self, GameUI)
end

function GameUI:enable(enable: boolean)
    if (guiUpdateConn) then
        guiUpdateConn:Disconnect()
        guiUpdateConn = nil
    end
    if (enable) then
        guiUpdateConn = RunService.RenderStepped:Connect(function(dt: number)  
            self:update(dt)
        end)
    end

    self.activeGuiObj = playerGui:WaitForChild(GAME_UI_NAME) :: ScreenGui
    if (self.activeGuiObj) then
        self.activeGuiObj.Enabled = enable
    end

    self.enabled = enable
end

function GameUI:reset()
    local currGui = playerGui:FindFirstChild(GAME_UI_NAME)
    if (currGui) then
        currGui:Destroy()
    end

    local newGuiClone = starterGameGui:Clone()
    newGuiClone.Parent = playerGui
    self.activeGuiObj = newGuiClone
end

function GameUI:update(dt: number)
end
 
function GameUI:destroy()
end

return GameUI.init()
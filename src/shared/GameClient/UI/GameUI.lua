local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local BaseUI = require(script.Parent.BaseUI)
local UIType = require(ReplicatedStorage.Shared.Enums.UIType)

local GAME_UI_NAME = "GameUI"
local ENABLE_FILTER = true
local DMG_OVERL_TRANSP_MIN = 0.35
local DMG_OVERL_TRANSP_MAX = 0.8
local DMG_OVERL_CHANGE_RATE = 0.8
local DMG_COLOR3 = Color3.new(1, 0, 0)
local HEAL_COLOR3 = Color3.new(0, 1, 0)
local DISPLAY_BLINK_TIME = 0.2

local playerGui = Players.LocalPlayer.PlayerGui
local starterGameGui = StarterGui.GameUI
assert(starterGameGui, `No StarterGui object with name {GAME_UI_NAME} found`)

local guiUpdateConn: RBXScriptConnection
local eventConns = {} :: {RBXScriptConnection}
-- for ez ref finding
local activeGuiObj = starterGameGui:Clone()
local activeFilterMesh: BasePart

local function setActiveFilterMesh(mesh: BasePart): BasePart
    if (activeFilterMesh) then
        activeFilterMesh:Destroy()
    end
    mesh.Parent = Workspace
    activeFilterMesh = mesh
    return mesh
end

local function onHealthChanged(newHP: number, diff: number, dmgType: string)
    local hpTextBox = activeGuiObj.Vitals.HealthTB
    local dmgOverlay = activeGuiObj.DamageOverlay

    dmgOverlay.BackgroundColor3 = (diff < 0) and DMG_COLOR3 or HEAL_COLOR3
    dmgOverlay.Transparency = 1 - math.clamp(
        math.abs(diff) * 0.01, DMG_OVERL_TRANSP_MIN, DMG_OVERL_TRANSP_MAX
    )
    hpTextBox.Text = tostring(newHP)
end

local function updateDmgOverlay(dt: number)
    local dmgOverlay = activeGuiObj.DamageOverlay

    local currHp = ClientRoot.getPlrData().health
    if (currHp <= 0) then
        dmgOverlay.Transparency = 1 -- - DMG_OVERL_TRANSP_MAX
        return
    end
    dmgOverlay.Transparency += dt * DMG_OVERL_CHANGE_RATE
    dmgOverlay = math.min(dmgOverlay.Transparency, 1)
end

local blinkTime = 0
local vis = true
local function updateDisplays(dt: number)
    local hpTextBox = activeGuiObj.Vitals.HealthTB
    local currHp = ClientRoot.getPlrData().health

    local hueVal = math.clamp((currHp - 25) * 0.01, 0, 0.32)
    hpTextBox.TextColor3 = Color3.fromHSV(
        hueVal, 1, 1
    )
    if (currHp <= 20) then
        if (not vis) then
            hpTextBox.TextColor3 = Color3.fromRGB(0, 0, 0)
        end
    end

    blinkTime += dt
    if (blinkTime > DISPLAY_BLINK_TIME) then
        blinkTime = 0
        vis = not vis
    end
end

local function onDeathStateChanged(isDead: boolean, lastDmgType: string)
    local dmgOverlay = activeGuiObj.DamageOverlay
    dmgOverlay.Transparency = 1

    if (isDead) then
        if (ENABLE_FILTER) then
            setActiveFilterMesh(activeGuiObj.Filters.RedDeathSphere)
        end
    else
        if (activeFilterMesh) then
            activeFilterMesh:Destroy()
        end
    end
	-- HealthLbl.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
	-- renderConn:Disconnect()
end

local function updateFilter()
    local character: Model = Players.LocalPlayer.Character
    if (not (character and character.PrimaryPart)) then
        return
    end 

    local isDead = ClientRoot.getPlrData().isDead
    if (isDead and activeFilterMesh) then
        activeFilterMesh.Position = Workspace.CurrentCamera.CFrame.Position
    end
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
    end
    if (enable) then
        guiUpdateConn = RunService.RenderStepped:Connect(function(dt: number)  
            self:update(dt)
        end)

        eventConns = {
            healthChanged = ClientRoot.signals.healthChanged.Event:Connect(onHealthChanged),
            deathStateChanged = ClientRoot.signals.deathStateChanged.Event:Connect(onDeathStateChanged),
        }
    else
        for _, conn: RBXScriptConnection in eventConns do
            conn:Disconnect()
        end
    end

    activeGuiObj = playerGui:WaitForChild(GAME_UI_NAME) :: ScreenGui
    if (activeGuiObj) then
        activeGuiObj.Enabled = enable
    end

    self.enabled = enable
end

function GameUI:reset()
    if (activeGuiObj) then
        activeGuiObj:Destroy()
    end

    local newGuiClone = starterGameGui:Clone()
    newGuiClone.Parent = playerGui
    activeGuiObj = newGuiClone
end

function GameUI:update(dt: number)
    updateDisplays(dt)
    updateDmgOverlay(dt)
    updateFilter()
end
 
function GameUI:destroy()
end

return GameUI.init()
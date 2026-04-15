local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local BaseUI = require(script.Parent.BaseUI)
local UIType = require(ReplicatedStorage.Shared.Enums.UIType)

local GAME_UI_NAME = "GameUI"
local ENABLE_DEATH_FILTER = true
local DMG_OVERL_TRANSP_MIN = 0.35
local DMG_OVERL_TRANSP_MAX = 0.8
local DMG_OVERL_CHANGE_RATE = 0.8
local DMG_COLOR3 = Color3.new(1, 0, 0)
local HEAL_COLOR3 = Color3.new(0, 1, 0)
local COLOR3_FULLBLACK = Color3.new(0, 0, 0)
local DISPLAY_BLINK_TIME = 0.2
local DEATH_FADE_DELAY = 0.6

local SPRITESHEET_TILE_SIZE = 64
local FACE_SPRITE_HEALTH_OFFSETS = {
    default = Vector2.new(0, 0),
    wounded0 = Vector2.new(1, 0),
    wounded1 = Vector2.new(2, 0),
    dead = Vector2.new(3, 0),
    godmode = Vector2.new(0, 1)
}
-- compute offsets
for ind: string, vec: Vector2 in pairs(FACE_SPRITE_HEALTH_OFFSETS) do
    FACE_SPRITE_HEALTH_OFFSETS[ind] = vec * SPRITESHEET_TILE_SIZE
end

local playerGui = Players.LocalPlayer.PlayerGui
local starterGameGui = StarterGui.GameUI
assert(starterGameGui, `No StarterGui object with name {GAME_UI_NAME} found`)

local guiUpdateConn: RBXScriptConnection
local eventConns = {} :: {RBXScriptConnection}
-- for ez ref finding
local activeGuiObj = starterGameGui:Clone()
local activeFilterMesh: BasePart

local pauseDmgOverlayUpd = false
local timeSinceDeath = 0

-- note: some (most) properties of the GUI assembly are predefined by starterGameGui
-- use this function to overwrite certain settings on reset
local function onResetUiSettings()
    activeGuiObj.DamageOverlay.Transparency = 0
    activeGuiObj.DamageOverlay.BackgroundColor3 = COLOR3_FULLBLACK
end

local function setActiveFilterMesh(mesh: BasePart): BasePart
    if (activeFilterMesh) then
        activeFilterMesh:Destroy()
    end
    local meshClone = mesh:Clone()
    meshClone.Parent = Workspace
    activeFilterMesh = meshClone
    return meshClone
end

local function onHealthChanged(newHP: number, diff: number, dmgType: string)
    local plrData = ClientRoot.getPlayerData()
    local hpTextBox = activeGuiObj.LowPanel.Vitals.HealthTB
    local dmgOverlay = activeGuiObj.DamageOverlay

    hpTextBox.Text = tostring(newHP)

    local function setDamageOverlay()
        if (newHP == 0) then
            dmgOverlay.Transparency = 1
            dmgOverlay.BackgroundColor3 = COLOR3_FULLBLACK
            return
        end
        -- dont set transparency when healing or leaving godmode
        if (newHP - diff <= 0 or newHP >= PlayerData.LIMITS.healthWithBonus) then
            return
        end
        dmgOverlay.BackgroundColor3 = (diff < 0) and DMG_COLOR3 or HEAL_COLOR3
        dmgOverlay.Transparency = 1 - math.clamp(
            math.abs(diff) * 0.01, DMG_OVERL_TRANSP_MIN, DMG_OVERL_TRANSP_MAX
        )
    end

    local function setFaceIcon()
        local faceImgLbl = activeGuiObj.LowPanel.CenterFrame.ImageLabel
        local inGodMode = plrData.godModeActive
        if (inGodMode) then
            faceImgLbl.ImageRectOffset = FACE_SPRITE_HEALTH_OFFSETS.godmode
        else
            if (newHP >= 65) then
                faceImgLbl.ImageRectOffset = FACE_SPRITE_HEALTH_OFFSETS.default
            elseif (newHP < 65 and newHP >= 30) then
                faceImgLbl.ImageRectOffset = FACE_SPRITE_HEALTH_OFFSETS.wounded0
            elseif (newHP < 30 and newHP > 0) then
                faceImgLbl.ImageRectOffset = FACE_SPRITE_HEALTH_OFFSETS.wounded1
            else
                faceImgLbl.ImageRectOffset = FACE_SPRITE_HEALTH_OFFSETS.dead
            end
        end
    end

    setDamageOverlay()
    setFaceIcon()
end

local function updateDmgOverlayTransp(dt: number)
    if (pauseDmgOverlayUpd) then 
        return
    end

    local dmgOverlay = activeGuiObj.DamageOverlay

    local currHp = ClientRoot.getPlayerData().health

    -- fade to black screen after dying
    if (currHp <= 0) then
        if (timeSinceDeath > DEATH_FADE_DELAY) then
            local newTransp = math.max(0, dmgOverlay.Transparency - dt * 0.55)
            dmgOverlay.Transparency = newTransp
        end
        return
    end
    dmgOverlay.Transparency += dt * DMG_OVERL_CHANGE_RATE
    dmgOverlay = math.min(dmgOverlay.Transparency, 1)
end

local blinkTime = 0
local vis = true
local function updateDisplays(dt: number)
    local hpTextBox = activeGuiObj.LowPanel.Vitals.HealthTB
    local currHp = ClientRoot.getPlayerData().health

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
    if (isDead) then
        local dmgOverlay = activeGuiObj.DamageOverlay
        dmgOverlay.Transparency = 1
        if (ENABLE_DEATH_FILTER) then
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

    if (activeFilterMesh) then
        activeFilterMesh.CFrame = Workspace.CurrentCamera.CFrame
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
    self:enable(false)

    if (activeGuiObj) then
        activeGuiObj:Destroy()
    end

    local newGuiClone = starterGameGui:Clone()
    newGuiClone.Parent = playerGui
    activeGuiObj = newGuiClone

    onResetUiSettings()
    self:enable(true)
end

function GameUI:update(dt: number)
    if (not activeGuiObj) then
        warn("Gui not loaded"); return
    end

    updateDisplays(dt)
    updateDmgOverlayTransp(dt)
    updateFilter()

    if (ClientRoot.getPlayerData().isDead) then
        timeSinceDeath += dt
    else
        timeSinceDeath = 0
    end
end
 
function GameUI:destroy()
end

return GameUI.init()
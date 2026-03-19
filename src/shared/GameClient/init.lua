--[[
    Main module for all client-side player and game logic.

    lots and lot of TODO here
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local Network = require(ReplicatedStorage.Shared.Network)
local CliApi = require(script.CliNetApi)
local SoundManager = require(ReplicatedStorage.Shared.SoundManager)
local CorePlayerUI = require(script.UI.CorePlayerUI)
local Controller = require(ReplicatedStorage.Shared.Controller)
local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)

local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local UIType = require(ReplicatedStorage.Shared.Enums.UIType)

local MIN_FALL_DMG_VEL = 65.0
local MIN_FALL_DMG = 5
local FALL_DMG_COOLDOWN = 0.25
local FALL_DMG_FAC = 0.0095
local FALL_DMG_OFFSET = MIN_FALL_DMG_VEL * MIN_FALL_DMG_VEL

local DEATH_SOUND_MAP = {
    [DamageType.NONE] = SoundManager.SOUND_ITEMS.DEATH,
    [DamageType.BLADE] = SoundManager.SOUND_ITEMS.DEATH,
    [DamageType.BLUNT] = SoundManager.SOUND_ITEMS.DEATH,
    [DamageType.BULLET] = SoundManager.SOUND_ITEMS.DEATH,
    [DamageType.EXPLOSION] = SoundManager.SOUND_ITEMS.DEATH,
    [DamageType.NAPALM] = SoundManager.SOUND_ITEMS.DEATH,
    [DamageType.PLASMA] = SoundManager.SOUND_ITEMS.DEATH,
    [DamageType.FALL] = SoundManager.SOUND_ITEMS.DEATH_FALL,
    [DamageType.DROWN] = SoundManager.SOUND_ITEMS.DEATH_DROWN,
}

local DMG_SOUND_ARR = {
    SoundManager.SOUND_ITEMS.DAMAGE_0,
    SoundManager.SOUND_ITEMS.DAMAGE_1,
    SoundManager.SOUND_ITEMS.DAMAGE_2,
    SoundManager.SOUND_ITEMS.DAMAGE_3,
}

local clientEvents = Network.clientEvents
local localPlr = Players.LocalPlayer

local simulation = Controller:getSimulation()
local camera = Controller:getCamera()
local rootPlrData = ClientRoot.getPlrData()
local rootSimData = ClientRoot.getSimData()
local rootGameData = ClientRoot.getGameData()

local lastFallVel = 0
local fallCooldown = 0

local updateConn: RBXScriptConnection
local charAddedConn: RBXScriptConnection
local charRemovingConn: RBXScriptConnection

------------------------------------------------------------------------------------------------------------------------
-- Network

local function onSetHealth(plr: Player, val: number)
    if (plr ~= localPlr) then
        return
    end

    ClientRoot.setHealth(val)
    if (rootPlrData.health <= 0) then
        ClientRoot.setIsDead(true)
    end
end

local cliREFunction = {
    [Network.serverEvents.playSound] = function(plr: Player, item: string, play: boolean)
        SoundManager:updatePlayerSound(plr, item, play)
    end,
    [Network.serverEvents.setHealth] = function(plr: Player, val: number)
        onSetHealth(plr, val)
    end
}

local cliFastREFunctions = {
    [Network.serverFastEvents.jointsDataToClient] = function(plr: Player, ...)
        -- TODO
    end,
}

CliApi.implementREvents(cliREFunction)
CliApi.implementFastREvents(cliFastREFunctions)

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local GameClient = {}

function GameClient.init()
    if (updateConn) then
        (updateConn :: RBXScriptConnection):Disconnect()
    end
    updateConn = RunService.PreSimulation:Connect(function(dt) 
        GameClient.update(dt) 
    end)

    GameClient.initPlayer()

    return GameClient
end

function GameClient.initPlayer()
    local function onCharAdded(character: Model)
        ClientRoot.setIsDead(false)
    end

    local function onCharRemoving(character: Model)
        CliApi.events[clientEvents.requestSpawn]:FireServer()
    end

    CliApi.events[clientEvents.requestSpawn]:FireServer()

    if (charAddedConn) then charAddedConn:Disconnect() end
    if (charRemovingConn) then charRemovingConn:Disconnect() end
    charAddedConn = Players.LocalPlayer.CharacterAdded:Connect(onCharAdded)
    charRemovingConn = Players.LocalPlayer.CharacterRemoving:Connect(onCharRemoving)
end

function GameClient.changeHealth(newHp: number, damageType: string?)
    if (newHp == rootPlrData.health) then
        return
    end
    local _damageType = damageType or DamageType.NONE

    -- play sounds
    if (newHp > 0 and newHp < rootPlrData.health) then
        local rmdSoundItem = DMG_SOUND_ARR[math.random(1, #DMG_SOUND_ARR)]
        SoundManager:updateGlobalSound(rmdSoundItem, true)
    end

    newHp = math.max(0, newHp)
    CliApi.events[clientEvents.requestChangeHealth]:FireServer(newHp, _damageType)
    ClientRoot.setHealth(newHp, _damageType)
end

function GameClient.onDeathStateChanged(isDead: boolean, lastDamageType: string)
    if (not isDead) then
        -- TODO: spawn / revive effects
        camera:activateFPDeathCam(false)
        return
    end
    
    simulation:toggleReadInput(false)
    camera:activateFPDeathCam(true)
    local deathSound = DEATH_SOUND_MAP[lastDamageType]
    SoundManager:updateGlobalSound(deathSound, true)
end

function GameClient.updateFallDamage(dt: number)
    local character = Players.LocalPlayer.Character
    local isDead = rootPlrData.isDead

    if (not character or isDead) then
        return
    end

    local primPart = character.PrimaryPart
    assert(primPart, "No primary part")

    local currFallVel = math.abs(math.min(primPart.AssemblyLinearVelocity.Y, 0))

    local damageConditions = 
        rootSimData.playerStateId == PlayerStateId.GROUND 
        and rootSimData.isGrounded 
        and lastFallVel >= MIN_FALL_DMG_VEL 
        and fallCooldown <= 0

    if (damageConditions) then
        local damage = math.floor((lastFallVel * lastFallVel - FALL_DMG_OFFSET) * FALL_DMG_FAC + MIN_FALL_DMG)
        local newHp = rootPlrData.health - damage
        GameClient.changeHealth(newHp, DamageType.FALL)
        fallCooldown = FALL_DMG_COOLDOWN
    end

    fallCooldown = math.max(0, fallCooldown - dt)
    lastFallVel = currFallVel
end

function GameClient.updateGameTime(dt: number, override: number?)
    local newTime = override or rootGameData.gameTime + dt
    ClientRoot.setGameTime(newTime)
end

function GameClient.updateSimData(dt: number)
    local stateShared = simulation:getStateShared()
    local currStateId = simulation:getCurrentStateId()

    ClientRoot.setIsGrounded(stateShared.grounded)
    ClientRoot.setIsDashing(stateShared.isDashing)
    ClientRoot.setCurrentPlayerStateId(currStateId)
end

------------------------------------------------------------------------------------------------------------------------
-- GameClient update
------------------------------------------------------------------------------------------------------------------------
function GameClient.update(dt: number)
    GameClient.updateGameTime(dt)
    GameClient.updateSimData(dt)
    GameClient.updateFallDamage(dt)
end

------------------------------------------------------------------------------------------------------------------------
-- Events
ClientRoot.signals.deathStateChanged.Event:Connect(GameClient.onDeathStateChanged)

------------------------------------------------------------------------------------------------------------------------

GameClient.init()

CorePlayerUI.disableAll()
CorePlayerUI.setActive(UIType.GAME)

return GameClient
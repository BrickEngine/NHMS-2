--[[
    Root module for all client-side scripts.
    Updated by GameClient.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)

local gameData = {
    gameTime = 0,
}
local simData = {
    playerStateId = PlayerStateId.NONE,
    isDashing = false,
    isGrounded = false,
}
local plrData: PlayerData.Data = PlayerData.createPlayerData(Players.LocalPlayer)

local function singleValChangedEvent(newVal: any, oldVal: any, bindEvent: BindableEvent)
    if (newVal ~= oldVal) then
        bindEvent:Fire(newVal)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local ClientRoot = {
    signals = {
        -- player data signals
        healthChanged = Instance.new("BindableEvent"),
        armorChanged = Instance.new("BindableEvent"),
        ammoChanged = Instance.new("BindableEvent"),
        inventoryChanged = Instance.new("BindableEvent"),
        weaponSwitched = Instance.new("BindableEvent"),
        deathStateChanged = Instance.new("BindableEvent"),
        killCountChanged = Instance.new("BindableEvent"),
        scoreChanged = Instance.new("BindableEvent"),
        effectAdded = Instance.new("BindableEvent"),
        -- sim state signals
        simStateChanged = Instance.new("BindableEvent"),
        isDashingChanged = Instance.new("BindableEvent"),
        isGroundedChanged = Instance.new("BindableEvent"),
    },
}

export type SimData = typeof(simData)
export type GameData = typeof(gameData)

-- Getters

function ClientRoot.getGameData(): GameData
    return gameData
end

function ClientRoot.getSimData(): SimData
    return simData
end

function ClientRoot.getPlrData(): PlayerData.Data
    return plrData
end

-- Setters

function ClientRoot.setGameTime(val: number)
    gameData.gameTime = val
end

function ClientRoot.setHealth(newHp: number, damageType: string?)
    local _damageType = damageType or DamageType.NONE
    if (newHp ~= plrData.health) then
        ClientRoot.signals.healthChanged:Fire(newHp, _damageType)
        plrData.lastDamageType = _damageType
    end
    plrData.health = newHp
end

function ClientRoot.setIsDead(isDead: boolean)
    if (isDead ~= plrData.isDead) then
        ClientRoot.signals.deathStateChanged:Fire(isDead, plrData.lastDamageType)
    end
    plrData.isDead = isDead
end

function ClientRoot.setCurrentPlayerStateId(newId: number)
    singleValChangedEvent(newId, simData.playerStateId, ClientRoot.signals.simStateChanged)
    simData.playerStateId = newId
end

function ClientRoot.setIsDashing(isDashing: boolean)
    singleValChangedEvent(isDashing, simData.isDashing, ClientRoot.signals.isDashingChanged)
    simData.isDashing = isDashing
end

function ClientRoot.setIsGrounded(val: boolean)
    simData.isGrounded = val
end

return ClientRoot
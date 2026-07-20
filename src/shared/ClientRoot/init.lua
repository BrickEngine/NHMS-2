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
    isGrounded = false,
    inWater = false,
    submerged = false,
    onWaterSurface = false,
    isDashing = false,
    nearWall = false,
    isRightSideWall = false,
}
local plrData: PlayerData.Data = PlayerData.createPlayerData(Players.LocalPlayer)

local function singleValChangedEvent(newVal: any, oldVal: any, bindEvent: BindableEvent)
    if (newVal == oldVal) then return end
    bindEvent:Fire(newVal)
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
        inventorySlotChanged = Instance.new("BindableEvent"),
        weaponSwitched = Instance.new("BindableEvent"),
        deathStateChanged = Instance.new("BindableEvent"),
        killCountChanged = Instance.new("BindableEvent"),
        scoreChanged = Instance.new("BindableEvent"),
        effectAdded = Instance.new("BindableEvent"),
        -- sim state signals
        --[[
            SimState signal info pattern:
            (newval, oldval)
        ]]
        simStateChanged = Instance.new("BindableEvent"),
        simDataChanged = Instance.new("BindableEvent"),
        isDashingChanged = Instance.new("BindableEvent"),
        isGroundedChanged = Instance.new("BindableEvent"),
        inWaterChanged = Instance.new("BindableEvent"),
        submergedChanged = Instance.new("BindableEvent"),
        onWaterSurfaceChanged = Instance.new("BindableEvent"),
        nearWallChanged = Instance.new("BindableEvent")
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

function ClientRoot.getPlayerData(): PlayerData.Data
    return plrData
end

-- Setters

function ClientRoot.setGameTime(val: number)
    gameData.gameTime = val
end

function ClientRoot.setHealth(newHp: number, damageType: string?)
    local _damageType = damageType or DamageType.NONE
    local hpDiff = newHp - plrData.health
    if (newHp ~= plrData.health) then
        ClientRoot.signals.healthChanged:Fire(newHp, hpDiff, _damageType)
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

function ClientRoot.setActiveInvSlot(newSlot: number)
    if (plrData.activeInvSlot == newSlot) then
        return
    end
    plrData.activeInvSlot = newSlot
    ClientRoot.signals.weaponSwitched:Fire(newSlot)
end

function ClientRoot.freeInventorySlot(slot: number)
    plrData.inventory[slot] = nil
    ClientRoot.signals.inventorySlotChanged:Fire(slot, false)
end

function ClientRoot.occupyInventorySlot(slot: number, contents: any)
    plrData.inventory[slot] = contents
    ClientRoot.signals.inventorySlotChanged:Fire(slot, true)
end

function ClientRoot.setCurrentPlayerStateId(newId: number)
    singleValChangedEvent(newId, simData.playerStateId, ClientRoot.signals.simStateChanged)
    simData.playerStateId = newId
end

function ClientRoot.setSimSharedData(
    grounded: boolean,
    inWater: boolean, 
    submerged: boolean, 
    onSurface: boolean,
    isDashing: boolean,
    nearWall: boolean,
    isRightSideWall: boolean
)
    singleValChangedEvent(grounded, simData.isGrounded, ClientRoot.signals.isGroundedChanged)
    singleValChangedEvent(inWater, simData.inWater, ClientRoot.signals.inWaterChanged)
    singleValChangedEvent(submerged, simData.submerged, ClientRoot.signals.submergedChanged)
    singleValChangedEvent(onSurface, simData.onWaterSurface, ClientRoot.signals.onWaterSurfaceChanged)
    singleValChangedEvent(isDashing, simData.isDashing, ClientRoot.signals.isDashingChanged)
    singleValChangedEvent(nearWall, simData.nearWall, ClientRoot.signals.nearWallChanged)
    simData.isGrounded = grounded
    simData.inWater = inWater
    simData.submerged = submerged
    simData.onWaterSurface = onSurface
    simData.isDashing = isDashing
    simData.nearWall = nearWall
    simData.isRightSideWall = isRightSideWall
end

return ClientRoot
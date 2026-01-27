--[[
    Root module for all client-side scripts.
    Updated by GameClient.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerState = require(ReplicatedStorage.Shared.Enums.PlayerState)

export type Counter = {
    t: number,
    cooldown: number
}

local data = {
    gameTime = 0.0,
    playerState = PlayerState.NONE,
    health = 100.0,
    armor = 100.0,
    isDashing = false,
    currentInvSlot = 0,
}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local ClientRoot = {
    signals = {
        inventoryChanged = Instance.new("BindableEvent"),
        playerStateChanged = Instance.new("BindableEvent"),
        weaponSwitched = Instance.new("BindableEvent"),
        healthChanged = Instance.new("BindableEvent"),
        effectAdded = Instance.new("BindableEvent")
    }
}

-- Getters
function ClientRoot.getPlayerState(): number
    return data.playerState
end

function ClientRoot.getIsDashing(): boolean
    return data.isDashing
end

-- Setters
function ClientRoot.setHealth(val: number): number
    data.health = val
    ClientRoot.signals.healthChanged:Fire(data.health)
    return data.health
end

function ClientRoot.setPlayerState(val: number): number
    data.playerState = val
    ClientRoot.signals.playerStateChanged:Fire(data.playerState)
    return data.playerState
end

function ClientRoot.setIsDashing(val: boolean): boolean
    data.isDashing = val
    return data.isDashing
end

return ClientRoot
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

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local ClientRoot = {
    playerState = PlayerState.NONE,
    health = 100.0,
    isDashing = false,
    gameTime = 0.0,
    currentInvSlot = 0,
}
ClientRoot.__index = ClientRoot

ClientRoot.Signals = {
    inventoryChanged = Instance.new("BindableEvent"),
    weaponSwitched = Instance.new("BindableEvent"),
    healthChanged = Instance.new("BindableEvent"),
    effectAdded = Instance.new("BindableEvent")
}

function ClientRoot.updateHealth(val: number): number
    ClientRoot.health = val
    ClientRoot.Signals.healthChanged:Fire(ClientRoot.health)
    return ClientRoot.health
end

function ClientRoot.getPlayerState(): string
    return ClientRoot.playerState
end

function ClientRoot.getIsDashing(): boolean
    return ClientRoot.isDashing
end

return ClientRoot
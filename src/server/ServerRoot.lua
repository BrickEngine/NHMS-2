--[[
    Core module for common server-side logic and events.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local Network = require(ReplicatedStorage.Shared.Network)
local ServNetApi = require(ServerScriptService.Game.ServNetApi)

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local ServerRoot = {
    signals = {
        playerDied = Instance.new("BindableEvent"),
        playerRevived = Instance.new("BindableEvent"),
        entitySpawned = Instance.new("BindableEvent"),
        entityDied = Instance.new("BindableEvent"),
        weaponAdded = Instance.new("BindableEvent"),
        weaponRemoved = Instance.new("BindableEvent"),
        effectAdded = Instance.new("BindableEvent"),
        effectRemoved = Instance.new("BindableEvent"),
    }
}

function ServerRoot.getPlayerData(plr: Player)
    return PlayerData.getPlayerData(plr)
end

function ServerRoot.createPlayerData(plr: Player)
    PlayerData.createPlayerData(plr)
end

function ServerRoot.removePlayerData(plr: Player)
    PlayerData.removePlayerData(plr)
end

function ServerRoot.changePlayerHealth(plr: Player, newHealth: number, damageType: string)
    local currPlrData = PlayerData.getPlayerData(plr)
    currPlrData.lastDamageType = damageType
    currPlrData.health = math.max(newHealth, 0)
    
    if (currPlrData.health == 0) then
        ServerRoot.killPlayer(plr)
    end
    ServNetApi.events[Network.serverEvents.setHealth]:FireAllClients(plr, currPlrData.health, damageType)
end

function ServerRoot.killPlayer(plr: Player)
    local plrData = PlayerData.getPlayerData(plr)

    if (plrData.isDead) then
        return
    end
    if (plrData.health ~= 0) then
        plrData.health = 0
        ServNetApi.events[Network.serverEvents.setHealth]:FireAllClients(plr, 0)
    end
    plrData.isDead = true
    ServerRoot.signals.playerDied:Fire(plr)
end

function ServerRoot.fullyHealPlayer(plr: Player, bonus: boolean?)
    local plrData = PlayerData.getPlayerData(plr)
    local newHp = if (bonus) then PlayerData.LIMITS.healthWithBonus else PlayerData.LIMITS.health
    plrData.isDead = false
    ServerRoot.changePlayerHealth(plr, newHp, DamageType.HEAL)

    if (plrData.isDead) then
        plrData.isDead = false
        ServerRoot.signals.playerRevived:Fire(plr)
    end
    ServNetApi.events[Network.serverEvents.setHealth]:FireAllClients(plr, plrData.health)
end

return ServerRoot
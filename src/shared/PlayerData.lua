--!strict
-- Helper module for managing data on client and server separately

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseWeapon = require(ReplicatedStorage.Shared.GameSystems.BaseWeapon)
local AmmoType = require(ReplicatedStorage.Shared.Enums.AmmoType)
local FuncUtil = require(ReplicatedStorage.Shared.Util.FuncUtil)

local data = {}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local PlayerData = {}

export type Data = {
    health: number,
    armor: number,
    ammoStorage: {[string]: number},
    inventory: {[number]: BaseWeapon.BaseWeapon?},
    currentInvSlot: number,
    isDead: boolean,
    kills: number,
    score: number,
}

PlayerData.DEFAULTS = table.freeze({
    health = 0,
    armor = 0,
    starterAmmo = {
        [AmmoType.BULLETS] = 0,
        [AmmoType.SHOTGUN_SHELLS] = 0,
        [AmmoType.GRENADES] = 0,
        [AmmoType.BOLTS] = 0,
        [AmmoType.FUEL_CELLS] = 0,
        [AmmoType.PLASMA_ORBS] = 0,
    },
    inventory = table.create(9, nil) :: {BaseWeapon.BaseWeapon?},
    currentInvSlot = 0,
    isDead = true,
    kills = 0,
    score = 0,
})

PlayerData.LIMITS = table.freeze({
    health = 100,
    healthWithBonus = 200,
    godHealth = 666,
    armor = 100,
    armorWithBonus = 200,
    godArmor = 666,
    ammoStorage = {
        [AmmoType.BULLETS] = 400,
        [AmmoType.SHOTGUN_SHELLS] = 60,
        [AmmoType.GRENADES] = 25,
        [AmmoType.BOLTS] = 80,
        [AmmoType.FUEL_CELLS] = 100,
        [AmmoType.PLASMA_ORBS] = 80,
    },
    kills = 999999,
    score = 999999,
})

PlayerData.DEFAULT_DATA = table.freeze({
    health = PlayerData.DEFAULTS.health,
    armor = PlayerData.DEFAULTS.armor,
    ammoStorage = {
        [AmmoType.BULLETS]          = PlayerData.DEFAULTS.starterAmmo[AmmoType.BULLETS],
        [AmmoType.SHOTGUN_SHELLS]   = PlayerData.DEFAULTS.starterAmmo[AmmoType.SHOTGUN_SHELLS],
        [AmmoType.GRENADES]         = PlayerData.DEFAULTS.starterAmmo[AmmoType.GRENADES],
        [AmmoType.BOLTS]            = PlayerData.DEFAULTS.starterAmmo[AmmoType.BOLTS],
        [AmmoType.FUEL_CELLS]       = PlayerData.DEFAULTS.starterAmmo[AmmoType.FUEL_CELLS],
        [AmmoType.PLASMA_ORBS]      = PlayerData.DEFAULTS.starterAmmo[AmmoType.PLASMA_ORBS],
    },
    inventory = PlayerData.DEFAULTS.inventory,
    currentInvSlot = PlayerData.DEFAULTS.currentInvSlot,
    isDead = PlayerData.DEFAULTS.isDead,
    kills = PlayerData.DEFAULTS.kills,
    score = PlayerData.DEFAULTS.score,
}) :: Data

function PlayerData.removePlayerData(plr: Player)
    if (not data[plr]) then
        warn(`No playerdata of {plr} to clear`); return
    end

    local data = data[plr] :: Data
    -- call destroy on weapons, if they exist
    if (data.inventory) then
        for i, weap: BaseWeapon.BaseWeapon? in pairs(data.inventory) do
            if (weap) then
                weap:destroy()
                data.inventory[i] = nil
            end
        end
    end

    data[plr] = nil
end

function PlayerData.createPlayerData(plr: Player): Data
    if (data[plr]) then
        warn(`existing data of {plr} was overwritten`); PlayerData.removePlayerData(plr)
    end

    local newData = FuncUtil.deepCopy(PlayerData.DEFAULT_DATA) :: Data
    data[plr] = newData

    return data[plr]
end

function PlayerData.getPlayerData(plr: Player): Data
    if (not data[plr]) then
        error(`No Data of {plr} found`)
    end
    return data[plr]
end

return PlayerData
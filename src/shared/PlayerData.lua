-- Helper module for managing data on client and server separately

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseWeapon = require(ReplicatedStorage.Shared.GameSystems.Weapons.Arsenal.BaseWeapon)
local AmmoType = require(ReplicatedStorage.Shared.Enums.AmmoType)
local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)
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
    inventory: {[number]: BaseWeapon.Weapon?},
    activeInvSlot: number,
    lastDamageType: string,
    godModeActive: boolean,
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
    inventory = table.create(8, nil) :: {BaseWeapon.Weapon?},
    activeInvSlot = 0,
    lastDamageType = DamageType.NONE,
    godModeActive = false,
    isDead = true,
    kills = 0,
    score = 0,
})

PlayerData.LIMITS = table.freeze({
    minHealth = 0,
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
    activeInvSlot = PlayerData.DEFAULTS.activeInvSlot,
    lastDamageType = PlayerData.DEFAULTS.lastDamageType,
    isDead = PlayerData.DEFAULTS.isDead,
    godModeActive = PlayerData.DEFAULTS.godModeActive,
    kills = PlayerData.DEFAULTS.kills,
    score = PlayerData.DEFAULTS.score,
}) :: Data

function PlayerData.removePlayerData(plr: Player)
    if (not data[plr]) then
        warn(`No playerdata of {plr} to clear`); return
    end

    local plrData = data[plr] :: Data
    -- call destroy on weapons, if they exist
    if (plrData.inventory) then
        for i, weap: BaseWeapon.Weapon? in pairs(plrData.inventory) do
            if (weap) then
                weap:destroy()
                plrData.inventory[i] = nil
            end
        end
    end

    data[plr] = nil
end

function PlayerData.createPlayerData(plr: Player): Data
    if (data[plr]) then
        warn(`existing data of {plr} was overwritten`); PlayerData.removePlayerData(plr)
    end

    local newData = FuncUtil.deepCopy(PlayerData.DEFAULT_DATA)
    data[plr] = newData

    return data[plr]
end

function PlayerData.getPlayerData(plr: Player): Data
    if (not data[plr]) then
        error(`No Data of {plr} found`)
    end
    return data[plr]
end

------------------------------------------------------------------------------------------------------------------------

-- -- Returns resulting new HP value from the operation
-- function PlayerData.changeHealth(plr: Player, newHp: number, dmgType: string): number
--     local plrData = PlayerData.getPlayerData(plr)

--     if (plrData.godModeActive) then
--         return plrData.health
--     end
--     plrData.health = newHp
--     plrData.lastDamageType = dmgType
--     return plrData.health
-- end

return PlayerData
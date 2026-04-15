--[[
    Module for creating and managing existing weapon objects
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)
local NumUID = require(ReplicatedStorage.Shared.Util.NumUID)
-- Weapons
local Sword = require(weaponsFolder.Arsenal.Sword)
local Plasma = require(ReplicatedStorage.Shared.GameSystems.Weapons.Arsenal.Plasma)

local MAX_WEAPON_IDS = 1000

local weaponUids = NumUID.new(MAX_WEAPON_IDS)

local WEAP_MODULE_MAP = {
    [WeaponName.SWORD] = Sword,
    [WeaponName.PLASMA_SPELL] = Plasma,
}

-- stores the uids of the weapons (and the respective owner model)
local ownedWeapons = {} :: {Model: {number}}
local unownedWeapons = {} :: {number}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local WeaponManager = {}

-- Creates and registers a weapon by enum name for a given owner-model
function WeaponManager.createWeapon(ownerMdl: Model?, weapName: string): (BaseWeapon.Weapon, number)
    local weapModule = WEAP_MODULE_MAP[weapName]
    if (not weapModule) then
        error(`No existing module for '{string}'`)
    end

    local newUid = weaponUids:alloc()
    local weapon = weapModule.new(newUid)
    weapon:update(0)
    weapon:setOwner(ownerMdl)
    weaponUids:assignObj(weapon, weapon.uid)

    if (ownerMdl) then
        local weapArr = ownedWeapons[ownerMdl] or {}
        ownedWeapons[ownerMdl] = table.insert(weapArr, weapon)
    else
        table.insert(unownedWeapons, weapon)
    end
    return weapon, newUid
end

function WeaponManager.destroyWeapon(id: number)
    local weapon: BaseWeapon.Weapon = weaponUids:getObjById(id)
    if (not weapon) then
        error(`No existing weapon for uid '{id}'`)
    end
    weapon:destroy()

    local success = weaponUids:release(id)
    if (not success) then
        error(`Unable to release uid '{id}'`)
    end
end

function WeaponManager.destroyAllWeaponsForOwner(ownerMdl: Model)
    if (ownedWeapons[ownerMdl]) then
        for _, id: number in pairs(ownedWeapons[ownerMdl]) do
            WeaponManager.destroyWeapon(id)
        end
        ownedWeapons[ownerMdl] = {}
    end
end

function WeaponManager.destroyAllUnownedWeapons()
    for _, weapId: number in pairs(unownedWeapons) do
        WeaponManager.destroyWeapon(weapId)
    end
    unownedWeapons = {}
end

function WeaponManager.destroyAllWeapons(weapNameList: {string})
    WeaponManager.destroyAllUnownedWeapons()
    for _, ownerMdl: Model in pairs(ownedWeapons) do
        if (ownerMdl) then
            WeaponManager.destroyAllWeaponsForOwner(ownerMdl)
        end
    end
end

return WeaponManager
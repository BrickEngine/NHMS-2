--[[
    Module for creating and managing existing weapon objects
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)

-- Weapons
local Sword = require(weaponsFolder.Arsenal.Sword)

local WEAP_MODULE_MAP = {
    [WeaponName.SWORD] = Sword,
    [WeaponName.PLASMA_SPELL] = Sword,
}

local ownedWeapons = {} :: {Model: {BaseWeapon.BaseWeapon}}
local unownedWeapons = {} :: {BaseWeapon.BaseWeapon}

local WeaponManager = {}

-- Creates and registers a weapon by enum name for a given owner-model
function WeaponManager.createWeapon(ownerMdl: Model?, weapName: string): any
    local weapModule = WEAP_MODULE_MAP[weapName]
    if (not weapModule) then
        error(`No existing module for '{string}'`)
    end

    local weapon = weapModule.new()
    weapon:setOwner(ownerMdl)

    if (ownerMdl) then
        local weapArr = ownedWeapons[ownerMdl] or {}
        ownedWeapons[ownerMdl] = table.insert(weapArr, weapon)
    else
        table.insert(unownedWeapons, weapon)
    end
    return weapon
end

function WeaponManager.destroyAllWeaponsForOwner(ownerMdl: Model)
    if (ownedWeapons[ownerMdl]) then
        for _, weap: BaseWeapon.BaseWeapon in pairs(ownedWeapons[ownerMdl]) do
            if (weap) then
                weap:destroy()
            end
        end
        ownedWeapons[ownerMdl] = {}
    end
end

function WeaponManager.destroyAllUnownedWeapons()
    for _, weap: BaseWeapon.BaseWeapon in pairs(unownedWeapons) do
        if (weap) then
            weap:destroy()
        end
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
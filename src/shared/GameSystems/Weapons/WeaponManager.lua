--[[
    Module for the creation and management of weapon objects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)
local NumUID = require(ReplicatedStorage.Shared.Util.NumUID)
-- Weapons
local Sword = require(weaponsFolder.Arsenal.Sword)
local Plasma = require(ReplicatedStorage.Shared.GameSystems.Weapons.Arsenal.Plasma)

local MAX_WEAPON_IDS = 1000

local WEAP_MODULE_MAP = {
    [WeaponName.SWORD] = Sword,
    [WeaponName.PLASMA_SPELL] = Plasma,
}

local weapUids = NumUID.new(MAX_WEAPON_IDS)

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

    local newUid = weapUids:alloc()
    local weapon = weapModule.new(newUid) :: BaseWeapon.Weapon
    weapon:setOwner(ownerMdl)
    weapUids:assignObj(weapon, weapon.uid)

    if (ownerMdl) then
        local weapArr = ownedWeapons[ownerMdl] or {}
        ownedWeapons[ownerMdl] = table.insert(weapArr, weapon)
    else
        table.insert(unownedWeapons, weapon)
    end
    return weapon, newUid
end

function WeaponManager.createWeaponForClient(ownerMdl: Model?, weapName: string, uid: number): BaseWeapon.Weapon
    if (not RunService:IsClient()) then
        warn("'createWeaponForClient' should be only called by the client")
    end

    local weapModule = WEAP_MODULE_MAP[weapName]
    if (not weapModule) then
        error(`No existing module for '{string}'`)
    end

    local weapon = weapModule.new(uid) :: BaseWeapon.Weapon
    weapon:setOwner(ownerMdl)
    return weapon
end

-- -- Creates and registers a weapon by enum name for an id and optional owner model
-- function WeaponManager.createWeaponWithId(ownerMdl: Model?, weapName: string, uid: number): BaseWeapon.Weapon
--     local weapModule = WEAP_MODULE_MAP[weapName]
--     if (not weapModule) then
--         error(`No existing module for '{string}'`)
--     end
--     if (not weapUids.occ[uid]) then
--         error(`Uid '{uid}' has not been allocated`)
--     end

--     local weapon = weapModule.new(uid)
--     weapon:setOwner(ownerMdl)
--     weapUids:assignObj(weapon, weapon.uid)

--     if (ownerMdl) then
--         local weapArr = ownedWeapons[ownerMdl] or {}
--         ownedWeapons[ownerMdl] = table.insert(weapArr, weapon)
--     else
--         table.insert(unownedWeapons, weapon)
--     end
--     return weapon
-- end

function WeaponManager.destroyWeapon(uid: number)
    local weapon: BaseWeapon.Weapon = weapUids:getObjById(uid)
    if (not weapon) then
        error(`No existing weapon for uid '{uid}'`)
    end
    weapon:destroy()

    local success = weapUids:release(uid)
    if (not success) then
        error(`Unable to release uid '{uid}'`)
    end
end

function WeaponManager.destroyAllWeaponsForOwner(ownerMdl: Model)
    if (ownedWeapons[ownerMdl]) then
        for _, uid: number in pairs(ownedWeapons[ownerMdl]) do
            WeaponManager.destroyWeapon(uid)
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

function WeaponManager.destroyAllWeapons()
    WeaponManager.destroyAllUnownedWeapons()
    for _, ownerMdl: Model in pairs(ownedWeapons) do
        if (ownerMdl) then
            WeaponManager.destroyAllWeaponsForOwner(ownerMdl)
        end
    end
end

return WeaponManager
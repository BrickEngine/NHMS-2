--[[
    Module for the creation and management of weapon objects.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)
local NumUID = require(ReplicatedStorage.Shared.Util.NumUID)
-- Weapons
local Sword = require(weaponsFolder.Arsenal.Sword)
local Plasma = require(ReplicatedStorage.Shared.GameSystems.Weapons.Arsenal.Plasma)
local Global = require(ReplicatedStorage.Shared.Global)

local WEAPON_STORE_FOLD_NAME = Global.FOLDER_NAMES.WEAPONS_LOCAL
local MAX_WEAPON_IDS = 1000

local WEAP_MODULE_MAP = {
    [WeaponName.SWORD] = Sword,
    [WeaponName.PLASMA_SPELL] = Plasma,
}

local weapUids = NumUID.new(MAX_WEAPON_IDS)

-- configure weapon models
local weapAssetFold = ReplicatedStorage.Assets.WeaponModels
for _, inst: Instance in pairs(weapAssetFold:GetDescendants()) do
    if (inst:IsA("BasePart")) then
        inst.CastShadow = false
        inst.Anchored = false
        inst.CanCollide = false
        inst.CollisionGroup = CollisionGroup.IGNORE
    end
end

if (RunService:IsClient()) then
   local weapInstContainer = Instance.new("Folder", Workspace)
    weapInstContainer.Name = WEAPON_STORE_FOLD_NAME 
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local WeaponManager = {}

-- Creates and registers a weapon by enum name for a given owner
function WeaponManager.createWeapon(owner: Player, weapName: string): (BaseWeapon.Weapon, number)
    local weapModule = WEAP_MODULE_MAP[weapName]
    if (not weapModule) then
        error(`No existing module for '{weapName}'`)
    end

    local newUid = weapUids:alloc()
    local weapon = weapModule.new(newUid, owner) :: BaseWeapon.Weapon
    weapUids:assignObj(weapon, weapon.uid)

    return weapon, newUid
end

function WeaponManager.checkWeaponRegisteredAndExist(uid: number)
    return weapUids:isOccupied(uid)
end

function WeaponManager.createWeaponForClient(owner: Player, weapName: string, uid: number): BaseWeapon.Weapon
    if (not RunService:IsClient()) then
        error("'createWeaponForClient' should be only called by the client")
    end

    local weapModule = WEAP_MODULE_MAP[weapName]
    if (not weapModule) then
        error(`No existing module for '{weapName}'`)
    end

    --print("############ ", uid, " --- ", owner, " ##################")
    weapUids:forceAlloc(uid)
    local weapon = weapModule.new(uid, owner) :: BaseWeapon.Weapon
    weapUids:assignObj(weapon, uid)

    return weapon
end

function WeaponManager.getWeapFromUid(uid: number): BaseWeapon.Weapon?
    return weapUids:getObjById(uid)
end

function WeaponManager.getWeapFromUidSecure(uid: number): BaseWeapon.Weapon
    local timeStart = os.clock()
    while (os.clock() - timeStart < 5) do
        local weapObj = weapUids:getObjById(uid)
        if weapObj then return weapObj end
        task.wait()
    end

    error(`Weapon UID '${uid}' not found after timeout`)
end

function WeaponManager.destroyWeapon(uid: number)
    local weapon: BaseWeapon.Weapon = weapUids:getObjById(uid)
    if (not weapon) then
        error(`No existing weapon for uid '{uid}'`)
    end
    weapon:destroy()

    if (RunService:IsServer()) then
        print(`Destroying weapon with uid '{uid}'`)

        local success = weapUids:release(uid)
        if (not success) then
            error(`Unable to release uid '{uid}'`)
        end
    elseif (RunService:IsClient()) then
        print(`Destroying local weapon with uid '{uid}'`)

        weapUids:forceRelease(uid)
    end
end

return WeaponManager
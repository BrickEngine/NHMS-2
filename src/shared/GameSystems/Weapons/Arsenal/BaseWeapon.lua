--!strict
--[[
    Abstract template class for player weapons.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmmoType = require(ReplicatedStorage.Shared.Enums.AmmoType)
local Schema = require(ReplicatedStorage.Shared.Util.Schema)

local function err()
    error("Cannot call function of abstract class BaseWeapon", 2)
end

local BaseWeapon = {}
BaseWeapon.__index = BaseWeapon

export type WeaponConf = {
    uid: number,
    name: string,
    iconId: string,
    owner: Model?,
    fireSchema: {[string]: (any?) -> boolean}?,
    weaponModel: Model?,
    slot: number,
    mainAmmoType: string?,
    hasInternalAmmo: boolean?,
    ammoCapacity: number?,
    ammoPerShot: number?,
    ammo: number?,
}

export type Weapon = {
    uid: number,
    name: string,
    iconId: string,
    owner: Model?,
    weaponModel: Model?,
    slot: number,
    mainAmmoType: string?,
    hasInternalAmmo: boolean?,
    ammoCapacity: number?,
    ammo: number?,

    fireLocked: boolean,

    -- uid must be assigned on creation
    new: (uid: number, (any)) -> Weapon,

    equip: (self: Weapon) -> (),
    unequip: (self: Weapon) -> (),
    reload: (self: Weapon) -> (),
    fire: (self: Weapon, pos: Vector3, dir: Vector3, params: any?) -> (),
    validateFireParams: (self: Weapon, params: any) -> (boolean, string?),
    createPickup: (self: Weapon) -> any,
    onHit: (self: Weapon) -> (),
    reset: (self: Weapon) -> (),
    update: (self: Weapon, dt: number) -> (),
    destroy: (self: Weapon) -> (),

    [string]: any
}

function BaseWeapon.new(weaponConf: WeaponConf)
    local self = setmetatable({}, BaseWeapon)

    self.uid = weaponConf.uid
    self.name = weaponConf.name
    self.iconId = weaponConf.iconId
    self.owner = weaponConf.owner or nil
    self.fireSchema = weaponConf.fireSchema or nil
    self.weaponModel = weaponConf.weaponModel or nil
    self.slot = weaponConf.slot
    self.mainAmmoType = weaponConf.mainAmmoType or AmmoType.NONE
    self.hasInternalAmmo = weaponConf.hasInternalAmmo or false
    self.ammoCapacity = weaponConf.ammoCapacity or 0
    self.ammoPerShot = weaponConf.ammoPerShot or 0
    self.ammo = weaponConf.ammo or 0

    self.fireLocked = false

    return self :: any
end

------------------------------------------------------------------------------------------------------------------------
-- global methods

function BaseWeapon:setOwner(ownerMdl: Model | nil)
    self.owner = ownerMdl
end

function BaseWeapon:validateFireParams(params: any?): (boolean, string?)
    if (not (self.fireSchema and params)) then
        return true, nil
    end
    return Schema.validate(params, self.fireSchema)
end

function BaseWeapon:isOwnedByLocalPlr()
    if (not RunService:IsClient()) then
        error("Can only be called by client")
    end
    return self.owner == (Players.LocalPlayer :: Player).Character
end

function BaseWeapon:getIsFireLocked()
    return self.fireLocked
end

------------------------------------------------------------------------------------------------------------------------

function BaseWeapon:equip()
    err()
end

function BaseWeapon:unequip()
    err()
end

function BaseWeapon:reload()
    err()
end

-- fireParams schema is validated via validateFireParams
function BaseWeapon:fire(pos: Vector3, dir: Vector3, fireParams: any?)
    err()
end

function BaseWeapon:onHit()
    err()
end

function BaseWeapon:reset()
    err()
end

function BaseWeapon:update(dt: number)
    err()
end

function BaseWeapon:destroy()
    err()
end

return BaseWeapon
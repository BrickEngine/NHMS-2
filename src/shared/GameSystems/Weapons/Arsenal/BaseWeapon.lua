--!strict
--[[
    Abstract template class for player weapons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmmoType = require(ReplicatedStorage.Shared.Enums.AmmoType)

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
    weaponModel: Model?,
    slot: number,
    mainAmmoType: string?,
    hasInternalAmmo: boolean?,
    ammoCapacity: number?,
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

    -- uid must be assigned on creation
    new: (uid: number, (any)) -> Weapon,

    equip: (self: Weapon) -> (),
    unequip: (self: Weapon) -> (),
    reload: (self: Weapon) -> (),
    fire: (self: Weapon, altFire: boolean, pos: Vector3, dir: Vector3) -> (),
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
    self.owner = weaponConf.owner
    self.weaponModel = weaponConf.weaponModel
    self.slot = weaponConf.slot
    self.mainAmmoType = weaponConf.mainAmmoType or AmmoType.NONE
    self.hasInternalAmmo = weaponConf.hasInternalAmmo or false
    self.ammoCapacity = weaponConf.ammoCapacity or 0
    self.ammo = weaponConf.ammo or 0

    return self :: any
end

function BaseWeapon:setOwner(ownerMdl: Model | nil)
    self.owner = ownerMdl
end

function BaseWeapon:equip()
    err()
end

function BaseWeapon:unequip()
    err()
end

function BaseWeapon:reload()
    err()
end

function BaseWeapon:fire(altFire: boolean, pos: Vector3, dir: Vector3)
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
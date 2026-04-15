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

--export type BaseWeapon = typeof(BaseWeapon)
export type Weapon = {
    uid: number,
    name: string,
    iconId: string,
    owner: Model?,
    weaponModel: Model?,
    slot: number,
    reloadable: boolean,
    usesAmmo: boolean,
    mainAmmoType: string,
    ammoCapacity: number,
    ammo: number,

    -- uid must be assigned on creation
    new: (uid: number, (any)) -> Weapon,

    equip: (self: Weapon) -> (),
    unequip: (self: Weapon) -> (),
    reload: (self: Weapon) -> (),
    fire: (self: Weapon) -> (),
    createPickup: (self: Weapon) -> any,
    onHit: (self: Weapon) -> (),
    reset: (self: Weapon) -> (),
    update: (self: Weapon, dt: number) -> (),
    destroy: (self: Weapon) -> (),

    [string]: any
}

function BaseWeapon.new(
    uid: number,
    name: string,
    iconId: string,
    owner: Model?,
    weaponModel: any,
    slot: number,
    reloadable: boolean,
    usesAmmo: boolean,
    mainAmmoType: string,
    ammoCapacity: number,
    ammo: number
): Weapon
    local self = setmetatable({}, BaseWeapon)

    self.uid = uid
    self.name = name
    self.iconId = iconId
    self.owner = owner
    self.weaponModel = weaponModel
    self.slot = slot
    self.reloadable = reloadable
    self.usesAmmo = usesAmmo 
    self.mainAmmoType = if (usesAmmo) then mainAmmoType else AmmoType.NONE
    self.ammoCapacity = if (usesAmmo) then ammoCapacity else 0
    self.ammo = if (usesAmmo) then ammo else 0

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

function BaseWeapon:fire()
    err()
end

function BaseWeapon:createPickup(): any
    err(); return nil
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
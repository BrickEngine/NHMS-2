--!strict
-- Abstract template class for player weapons.

local function err()
    error("cannot call from abstract class BaseWeapon", 2)
end

local BaseWeapon = {}
BaseWeapon.__index = BaseWeapon

export type BaseWeapon = typeof(BaseWeapon)

function BaseWeapon.new(
    name: string,
    iconId: string,
    owner: Player,
    weaponModel: any,
    ammoCapacity: number,
    ammo: number,
    reloadable: boolean
)
    local self = setmetatable({}, BaseWeapon)

    self.name = name
    self.iconId = iconId
    self.owner = owner
    self.weaponModel = weaponModel
    self.ammoCapacity = ammoCapacity
    self.ammo = ammo
    self.reloadable = reloadable

    return self
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
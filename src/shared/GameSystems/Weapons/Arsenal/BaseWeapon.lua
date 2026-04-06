--!strict
-- Abstract template class for player weapons.

local function err()
    error("Cannot call function of abstract class BaseWeapon", 2)
end

local BaseWeapon = {}
BaseWeapon.__index = BaseWeapon

--export type BaseWeapon = typeof(BaseWeapon)
export type BaseWeapon = {
    name: string,
    iconId: string,
    owner: Model?,
    weaponModel: Model?,
    slot: number,
    reloadable: boolean,
    usesAmmo: boolean,
    ammoCapacity: number,
    ammo: number,
    [string]: any,

    equip: (self: BaseWeapon) -> (),
    unequip: (self: BaseWeapon) -> (),
    reload: (self: BaseWeapon) -> (),
    fire: (self: BaseWeapon) -> (),
    createPickup: (self: BaseWeapon) -> any,
    onHit: (self: BaseWeapon) -> (),
    reset: (self: BaseWeapon) -> (),
    update: (self: BaseWeapon, dt: number) -> (),
    destroy: (self: BaseWeapon) -> ()
}

function BaseWeapon.new(
    name: string,
    iconId: string,
    owner: Model?,
    weaponModel: any,
    slot: number,
    reloadable: boolean,
    usesAmmo: boolean,
    ammoCapacity: number,
    ammo: number
)
    local self = setmetatable({}, BaseWeapon)

    self.name = name
    self.iconId = iconId
    self.owner = owner
    self.weaponModel = weaponModel
    self.slot = slot
    self.reloadable = reloadable
    self.usesAmmo = usesAmmo
    self.ammoCapacity = if (usesAmmo) then ammoCapacity else 0
    self.ammo = if (usesAmmo) then ammo else 0

    return self
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
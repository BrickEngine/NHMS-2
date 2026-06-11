--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local AmmoType = require(ReplicatedStorage.Shared.Enums.AmmoType)
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)

local Plasma = setmetatable({} :: BaseWeapon.Weapon, BaseWeapon)
Plasma.__index = Plasma

function Plasma.new(uid: number)
    local self = BaseWeapon.new({
        uid = uid,
        name = WeaponName.PLASMA_SPELL,
        iconId = "rbxassetid://0",
        owner = nil,
        weaponModel = nil,
        slot = 2,
        mainAmmoType = AmmoType.PLASMA_ORBS
    })

    return setmetatable(self, Plasma) :: any
end

function Plasma:equip()
    print("EQUIPPING PLASMA")
end

function Plasma:unequip()
    print("UNEQUIPPING PLASMA")
end

function Plasma:reload()
end

function Plasma:fire()
    print("PLASMAAA")
end

function Plasma:createPickup(): any
    return nil
end

function Plasma:onHit()
end

function Plasma:reset()
end

function Plasma:update(dt: number)
end

function Plasma:destroy()
end

return Plasma
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local AmmoType = require(ReplicatedStorage.Shared.Enums.AmmoType)
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)

local Plasma = setmetatable({}, BaseWeapon)
Plasma.__index = Plasma

function Plasma.new(uid: number)
    local self = BaseWeapon.new(
        uid,
        WeaponName.SWORD,
        "rbxassetid://0",
        nil,
        nil,
        0,
        false,
        false,
        AmmoType.NONE,
        0,
        0
    )

    return setmetatable(self, Plasma) :: any
end

function Plasma:equip()
end

function Plasma:unequip()
end

function Plasma:reload()
end

function Plasma:fire()
    print("PLASMAAAA")
end

function Plasma:createPickup(): any
    return nil
end

function Plasma:onHit()
end

function Plasma:reset()
end

function Plasma:update(dt: number)
    print("update plasma")
end

function Plasma:destroy()
end

return Plasma
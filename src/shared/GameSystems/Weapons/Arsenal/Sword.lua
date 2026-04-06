--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)

local Sword = setmetatable({}, BaseWeapon)
Sword.__index = Sword

function Sword.new()
    local self = BaseWeapon.new(
        WeaponName.SWORD,
        "rbxassetid://0",
        nil,
        nil,
        0,
        false,
        false,
        0,
        0
    )

    return self
end

function Sword:equip()
end

function Sword:unequip()
end

function Sword:reload()
end

function Sword:fire()
end

function Sword:createPickup(): any
    return nil
end

function Sword:onHit()
end

function Sword:reset()
end

function Sword:update(dt: number)
    print("update sword")
end

function Sword:destroy()
end

return Sword
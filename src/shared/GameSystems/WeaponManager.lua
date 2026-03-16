local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(ReplicatedStorage.Shared.GameSystems.BaseWeapon)

local WeaponManager = {}

WeaponManager.WeaponsList = {}

function WeaponManager.createWeapon(weapName: string): any
    return nil
end

function WeaponManager.resetWeapon(weapName: string)
    
end

function WeaponManager.resetAllWeapons(weapNameList: {string})
    
end

return WeaponManager
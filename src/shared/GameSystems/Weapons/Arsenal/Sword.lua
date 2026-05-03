--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)
local Network = require(ReplicatedStorage.Shared.Network)

-- client only modules
local InputManager
local CliApi

if (RunService:IsClient()) then
    InputManager = require(ReplicatedStorage.Shared.InputManager)
    CliApi = require(ReplicatedStorage.Shared.GameClient.CliNetApi)
end

local localPlr = Players.LocalPlayer :: Player
local mdlFold = ReplicatedStorage.Assets.WeaponModels.Sword

local Sword = setmetatable({}, BaseWeapon)
Sword.__index = Sword

function Sword.new(uid: number)
    local swordModel = mdlFold.ClassicSword:Clone()
    
    local self: BaseWeapon.Weapon = BaseWeapon.new({
        uid = uid,
        name = WeaponName.SWORD,
        iconId = "rbxassetid://0",
        owner = nil, -- ownerMdl
        weaponModel = swordModel,
        slot = 1
    })

    return setmetatable(self, Sword) :: any
end

function Sword:equip()
    print("EQUIPPING SWORD")
    task.wait(0.5)
end

function Sword:unequip()
    print("UNEQUIPPING SWORD")
    task.wait(0.5)
end

function Sword:reload()
end

function Sword:fire(altFire: boolean)

end

function Sword:onHit()
end

function Sword:reset()
end

function Sword:update(dt: number)
    if (not RunService:IsClient()) then
        error("cannot run on server")
    end
    -- update for other players

    --TODO
    -- update local player
    if (self.owner == localPlr.Character) then
        local fireInp, altFireInp = InputManager:getFireKeysDown()

        if (fireInp or altFireInp) then
            self:fire(altFireInp)
            --CliApi.events[Network.clientEvents.requestFireWeapon]:FireServer(self.uid, altFireInp)
        end
    end
end

function Sword:destroy()
    print("destroying sword")
    if (self.weaponModel) then
        (self.weaponModel :: Model):Destroy()
    end
end

return Sword
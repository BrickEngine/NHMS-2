--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)
local Schema = require(ReplicatedStorage.Shared.Util.Schema)
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

export type SwordFireParams = {
    throw: boolean,
    throwspeed: number
}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Sword = setmetatable({}, BaseWeapon)
Sword.__index = Sword

function Sword.new(uid: number)
    local swordModel = mdlFold.ClassicSword:Clone()

    local swordSchema = {
        throwing = Schema.boolean(),
    }
    
    local self: BaseWeapon.Weapon = BaseWeapon.new({
        uid = uid,
        name = WeaponName.SWORD,
        iconId = "rbxassetid://0",
        owner = nil,
        fireSchema = swordSchema,
        weaponModel = swordModel,
        slot = 1
    })

    return setmetatable(self, Sword) :: any
end

function Sword:equip()
    if (self.owner ~= localPlr.Character) then
        return
    end

    print("EQUIPPING SWORD")
    if (not self.owner) then
        error("No weapon owner")
    end

    local weapModel: Model = self.weaponModel
    local owner: Model = self.owner
    assert(weapModel.PrimaryPart, `Model '{weapModel}' has no primary part`)
    assert(owner.PrimaryPart, `Owner model '{owner}' has no primary part`)

    weapModel.Parent = self.owner
    weapModel.PrimaryPart.CFrame = CFrame.new(owner.PrimaryPart.CFrame.Position)


    task.wait(0.5)
    --TweenService:Create(instance, tweenInfo, propertyTable)
end

function Sword:unequip()
    if (self.owner ~= localPlr.Character) then
        return
    end

    print("UNEQUIPPING SWORD")
    if (not self.owner) then
        error("No weapon owner")
    end
    task.wait(0.5)
end

function Sword:reload()
end

function Sword:fire(pos: Vector3, dir: Vector3, fireParams: SwordFireParams)

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

        local userMdl = self.owner :: Model
        local userPrimPart = userMdl.PrimaryPart

        if (not userPrimPart) then 
            error("No primary part")
        end

        local pos = userPrimPart.Position
        local dir = Workspace.CurrentCamera.CFrame.LookVector

        if (fireInp or altFireInp) then
            self:fire(altFireInp)
            CliApi.events[Network.clientEvents.requestFireWeapon]:FireServer(pos, dir, altFireInp)
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
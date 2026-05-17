--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local WeaponCommon = require(ReplicatedStorage.Shared.GameSystems.Weapons.WeaponCommon)
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

local CF_CAM_WEAP_OFFS = 
    CFrame.new(Vector3.new(0.95,-0.2,-1.25)) 
    * CFrame.fromEulerAnglesXYZ(math.rad(75), math.rad(180), math.rad(120))

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
    local weapModel: Model = self.weaponModel
    local ownerMdl: Model = self.owner
    assert(weapModel.PrimaryPart, `Model '{weapModel}' has no primary part`)
    assert(ownerMdl.PrimaryPart, `Owner model '{ownerMdl}' has no primary part`)

    --WeaponCommon.joinWeaponToOwnerPrimPart(weapModel, ownerMdl)

    -- case for other players
    if (self.owner ~= localPlr.Character) then
        -- TODO
        return
    end

    print("EQUIPPING SWORD")
    if (not self.owner) then
        error("No weapon owner")
    end

    weapModel.PrimaryPart.Anchored = true
    weapModel.Parent = self.owner
    weapModel.PrimaryPart.CFrame = CFrame.new(ownerMdl.PrimaryPart.CFrame.Position)

    --TweenService:Create(instance, tweenInfo, propertyTable)
end

function Sword:unequip()
    -- case for other players
    if (self.owner ~= localPlr.Character) then
        -- TODO
        return
    end

    local weapModel: Model = self.weaponModel
    local ownerMdl: Model = self.owner
    assert(weapModel.PrimaryPart, `Model '{weapModel}' has no primary part`)
    assert(ownerMdl.PrimaryPart, `Owner model '{ownerMdl}' has no primary part`)

    weapModel.Parent = localPlr.Backpack

    print("UNEQUIPPING SWORD")
    if (not self.owner) then
        error("No weapon owner")
    end
end

function Sword:reload()
end

function Sword:fire(pos: Vector3, dir: Vector3, fireParams: SwordFireParams)
    if (self:isOwnedByLocalPlr()) then
        CliApi.events[Network.clientEvents.requestFireWeapon]:FireServer(pos, dir, fireParams)
    end

end

function Sword:onHit()
end

function Sword:reset()
    self.fireLocked = false
end

function Sword:update(dt: number)
    if (not RunService:IsClient()) then
        error("cannot run on server")
    end

    -- do not update for other players
    if (not self:isOwnedByLocalPlr()) then
        return
    end

    local charMdl = self.owner :: Model
    local weapModel: Model = self.weaponModel

    local charPrimPart = charMdl.PrimaryPart
    local weapPrimPart = weapModel.PrimaryPart
    local charPos = charPrimPart.CFrame.Position
    local camera = Workspace.CurrentCamera
    local camCFrame = camera.CFrame
    local fireInp, altFireInp = InputManager:getFireKeysDown()

    if (not charPrimPart) then 
        error("No primary part")
    end

    weapPrimPart.CFrame = camCFrame * CF_CAM_WEAP_OFFS

    if (fireInp or altFireInp) then
        self:fire(altFireInp)
    end
end

function Sword:destroy()
    print("destroying sword")
    if (self.weaponModel) then
        (self.weaponModel :: Model):Destroy()
    end
end

return Sword
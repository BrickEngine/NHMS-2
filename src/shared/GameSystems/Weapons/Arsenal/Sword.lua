--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
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

------------------------------------------------------------------------------------------------------------------------

local CF_DEF_WEAP_OFFS = 
    CFrame.new(Vector3.new(0.95,-1.4,-1.25)) 
    * CFrame.fromEulerAnglesXYZ(math.rad(0), math.rad(0), math.rad(0))

local CF_UNEQUIP_TARGET = 
    CFrame.new(Vector3.new(0, -4, 0))

local CF_SWING_TARGET = 
    CFrame.new(Vector3.new(0.95,-1.4,-1.25)) 
    * CFrame.fromEulerAnglesXYZ(math.rad(-90), math.rad(0), math.rad(0))

--local VEC3_UNEQUIP_TARGET = Vector3.new(0, 0, -4)
local EQUIP_LERP_FAC = 18
local EQUIP_DURATION = 0.25
local SWING_RATE = 0.33

local VEC3_UP = Vector3.new(0, 1, 0)

local localPlr = Players.LocalPlayer :: Player
local mdlFold = ReplicatedStorage.Assets.WeaponModels.Sword

local inSwing = false
local altFireCharging = false

local equipUpdateConn: RBXScriptConnection
local unequipUpdateConn: RBXScriptConnection

local function updateSwordSwing(dt: number)
    
end

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
    if (not self.owner) then
        error("No weapon owner")
    end

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

    if (unequipUpdateConn) then
        unequipUpdateConn:Disconnect()
    end

    local downPosOffsCFrame = CF_DEF_WEAP_OFFS * CF_UNEQUIP_TARGET
    local camCFrame = Workspace.CurrentCamera.CFrame
    local targetOffsLerpCFrame = downPosOffsCFrame
    local equipTime = 0

    weapModel.PrimaryPart.Anchored = true
    weapModel.Parent = self.owner
    weapModel.PrimaryPart.CFrame = camCFrame * downPosOffsCFrame

    equipUpdateConn = RunService.PreRender:Connect(function(dt: number)
        camCFrame = Workspace.CurrentCamera.CFrame
        targetOffsLerpCFrame = targetOffsLerpCFrame:Lerp(CF_DEF_WEAP_OFFS, dt * EQUIP_LERP_FAC)

        weapModel.PrimaryPart.CFrame = camCFrame * targetOffsLerpCFrame
        
        if (equipTime >= EQUIP_DURATION) then
            equipUpdateConn:Disconnect()
        end
        equipTime += dt
    end)

    task.wait(EQUIP_DURATION)
end

function Sword:unequip()
    if (not self.owner) then
        error("No weapon owner")
    end

    -- case for other players
    if (self.owner ~= localPlr.Character) then
        -- TODO
        return
    end
    print("UNEQUIPPING SWORD")

    if (equipUpdateConn) then
        equipUpdateConn:Disconnect()
    end

    local weapModel: Model = self.weaponModel
    local ownerMdl: Model = self.owner
    assert(weapModel.PrimaryPart, `Model '{weapModel}' has no primary part`)
    assert(ownerMdl.PrimaryPart, `Owner model '{ownerMdl}' has no primary part`)

    local downPosOffsCFrame = CF_DEF_WEAP_OFFS * CF_UNEQUIP_TARGET
    local camCFrame = Workspace.CurrentCamera.CFrame
    local targetOffsLerpCFrame = CF_DEF_WEAP_OFFS
    local unequipTime = 0

    weapModel.PrimaryPart.CFrame = camCFrame * CF_DEF_WEAP_OFFS

    unequipUpdateConn = RunService.PreRender:Connect(function(dt: number)
        camCFrame = Workspace.CurrentCamera.CFrame
        targetOffsLerpCFrame = targetOffsLerpCFrame:Lerp(downPosOffsCFrame, dt * EQUIP_LERP_FAC)

        weapModel.PrimaryPart.CFrame = camCFrame * targetOffsLerpCFrame

        unequipTime += dt
        if (unequipTime >= EQUIP_DURATION) then
            unequipUpdateConn:Disconnect()
        end
    end)

    WeaponCommon.dynOffset.reset()

    task.wait(EQUIP_DURATION)
    weapModel.Parent = localPlr.Backpack
end

function Sword:reload()
end

function Sword:fire(pos: Vector3, dir: Vector3, fireParams: SwordFireParams)
    local weapModel: Model = self.weaponModel
    local weapPrimPart = weapModel.PrimaryPart

    local swordSlashSound: Sound = weapPrimPart.SwordSlash
    swordSlashSound:Play()

    if (self:isOwnedByLocalPlr()) then
        -- TODO
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
    local currCharVel = charMdl.PrimaryPart.AssemblyLinearVelocity
    local camCFrame = Workspace.CurrentCamera.CFrame
    local fireInp, altFireInp = InputManager:getFireKeysDown()

    if (not charPrimPart) then 
        error("No primary part")
    end

    --weapPrimPart.CFrame = camCFrame * CF_CAM_WEAP_OFFS
    weapPrimPart.CFrame = WeaponCommon.dynOffset.calc(
        dt, currCharVel, camCFrame * CF_DEF_WEAP_OFFS
    )
    

    if (fireInp) then
        --self.fireLocked = true
    end

    if (fireInp or altFireInp) then
        self.fireLocked = true
        self:fire(altFireInp)
    end
end

function Sword:destroy()
    print("destroying sword")
    if (self.weaponModel) then
        (self.weaponModel :: Model):Destroy()
    end

    if (equipUpdateConn) then
        equipUpdateConn:Disconnect()
    end
    if (unequipUpdateConn) then
        unequipUpdateConn:Disconnect()
    end
end

return Sword
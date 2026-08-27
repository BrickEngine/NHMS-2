--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local WeaponCommon = require(ReplicatedStorage.Shared.GameSystems.Weapons.WeaponCommon)
local Global = require(ReplicatedStorage.Shared.Global)
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

-- local CF_SWING_TARGET = 
--     CFrame.new(Vector3.new(0.95,-1.4,-1.25)) 
--     * CFrame.fromEulerAnglesXYZ(math.rad(-90), math.rad(0), math.rad(0))

--local VEC3_UNEQUIP_TARGET = Vector3.new(0, 0, -4)
local EQUIP_LERP_FAC = 18
local EQUIP_DURATION = 0.25
local SWING_COOLDOWN = 0.55
local THROW_COOLDOWN = 1.7
local THROW_MINTIME = 0.8
local SWING_ANIM_SPEED = 10

local SLOW_SPIN_SOUND_SPEED = 20.5
local FAST_SPIN_SOUND_SPEED = 40
local SLOW_SPIN_SPEED = 3
local FAST_SPIN_SPEED = 4

local BASE_THROW_SPEED = 70
local BONUS_THROW_SPEED = 25

local ANIM_IDS = table.freeze({
    SWING = "rbxassetid://102246589048865",
    PARRY = "rbxassetid://127066524649533"
})

local SOUND_IDS = table.freeze({
    HIT = "rbxassetid://109675024264804",
    LAUNCH = "rbxassetid://112053896516106",
    SLICE = "rbxassetid://116173653232904",
    SPIN = "rbxassetid://138269694368715",
    SWORD_LUNGE = "http://www.roblox.com/asset/?id=12222208",
    SWORD_SLASH = "http://www.roblox.com/asset/?id=12222216",
    UNSHEATH = "http://www.roblox.com/asset/?id=12222225",
})

local SOUND_DATA = table.freeze({
    [SOUND_IDS.HIT] = {
        Volume = 1,
        PlaybackSpeed = 1.8
    },
    [SOUND_IDS.SLICE] = {
        Volume = 1.25
    },
    [SOUND_IDS.SPIN] = {
        Volume = 0.8,
        Looped = true,
        PlaybackSpeed = 4,
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.1, 0.725)
    },
    [SOUND_IDS.SWORD_LUNGE] = {
        Volume = 0.6
    },
    [SOUND_IDS.SWORD_SLASH] = {
        Volume = 0.7,
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.39, 9999)
    },
})

local PI_2 = math.pi * 2

local localPlr = Players.LocalPlayer :: Player
local mdlFold = ReplicatedStorage.Assets.WeaponModels.Sword

local fireSignal = false
local updatePreFire = false
local fireHoldTime = 0
local fireCooldownTime = 0
local currSpinAng = 0 -- rad

local currFireParams: SwordFireParams?

local animationController: AnimationController?
local animator: Animator?
local animationTracks = {} :: {[string]: AnimationTrack}
local sounds = {} :: {[string]: Sound}

local equipUpdateConn: RBXScriptConnection
local unequipUpdateConn: RBXScriptConnection

local function createInitAnims()
    assert(animationController, "No AnimationController instance")
    assert(animator, "No animator instance")

    for name: string, id: string in pairs(ANIM_IDS) do
        local newAnimation = Instance.new("Animation", animator)
        newAnimation.Name = name
        newAnimation.AnimationId = id

        local animTrack = animator:LoadAnimation(newAnimation)
        animationTracks[id] = animTrack
    end
end

export type SwordFireParams = {
    altFire: boolean,
    throwSpeed: number
}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Sword = setmetatable({}, BaseWeapon)
Sword.__index = Sword

function Sword.new(uid: number, ownerMdl: Model?)
    local swordModel = mdlFold.ClassicSword:Clone()
    assert(swordModel.PrimaryPart, "Sword model does not have a primary part")

    swordModel.Parent = ReplicatedStorage
    for _, p: Instance in (swordModel:GetChildren()) do
        if (p:IsA("BasePart")) then
            p.Anchored = (p == swordModel.PrimaryPart) and true or false
        end
    end
    
    if (RunService:IsClient()) then
        -- anims
        local foundAnimController = swordModel:FindFirstChildWhichIsA("AnimationController")
        if (foundAnimController) then
            foundAnimController:Destroy()
        end

        animationController = Instance.new("AnimationController", swordModel)
        animator = Instance.new("Animator", animationController)
        createInitAnims()

        -- sounds
        for _, soundId: string in pairs(SOUND_IDS) do
            local newSound = Instance.new("Sound", swordModel.PrimaryPart)
            newSound.SoundId = soundId

            if (SOUND_DATA[soundId]) then
                for prop: string, val: any in pairs(SOUND_DATA[soundId]) do
                    newSound[prop] = val
                end
            end
            sounds[soundId] = newSound
        end
    end

    local self: BaseWeapon.Weapon = BaseWeapon.new({
        uid = uid,
        name = WeaponName.SWORD,
        iconId = "rbxassetid://0",
        owner = ownerMdl or nil,
        fireSchema = {
            altFire = Schema.boolean(),
            throwSpeed = Schema.number()
        },
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
    if (not self:isOwnedByLocalPlr()) then
        -- TODO
        return
    end

    -- below here: everything that happens for weapon owner only
    print("EQUIPPING SWORD")

    if (unequipUpdateConn) then
        unequipUpdateConn:Disconnect()
    end

    local downPosOffsCFrame = CF_DEF_WEAP_OFFS * CF_UNEQUIP_TARGET
    local camCFrame = Workspace.CurrentCamera.CFrame
    local targetOffsLerpCFrame = downPosOffsCFrame
    local equipTime = 0

    weapModel.Parent = Workspace:WaitForChild(Global.FOLDER_NAMES.WEAPONS_LOCAL) --self.owner
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
    if (not self:isOwnedByLocalPlr()) then
        -- TODO
        return
    end

    -- below here: everything that happens for weapon owner only
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

    for _, s: Sound in pairs(sounds) do
        if (s.IsPlaying) then
            s:Stop()
        end
    end

    -- reset local and common vars
    WeaponCommon.dynOffset.reset()
    self:reset()

    task.wait(EQUIP_DURATION)
    weapModel.Parent = localPlr.Backpack
end

function Sword:reload()
end

function Sword:fire(pos: Vector3, dir: Vector3, fireParams: SwordFireParams)
    local weapModel: Model = self.weaponModel
    local weapPrimPart = weapModel.PrimaryPart
    
    if (not fireParams.altFire) then
        animationTracks[ANIM_IDS.SWING]:Play(0, 1, SWING_ANIM_SPEED)
        sounds[SOUND_IDS.SWORD_SLASH]:Play()
    else
        sounds[SOUND_IDS.LAUNCH]:Play()
    end

    if (self:isOwnedByLocalPlr()) then
        -- TODO
        CliApi.events[Network.clientEvents.requestFireWeapon]:FireServer(pos, dir, fireParams)
    end

    print(fireParams.throwSpeed)

end

function Sword:onHit()
end

function Sword:reset()
    self.fireLocked = false
    updatePreFire = false
    fireCooldownTime = 0
    fireHoldTime = 0
    currSpinAng = 0
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

    --weapPrimPart.CFrame = camCFrame * CF_DEF_WEAP_OFFS

    local anyInput = fireInp or altFireInp
    if (not self.fireLocked and anyInput) then
        currFireParams = {
            altFire = altFireInp,
            throwSpeed = BASE_THROW_SPEED
        }
        fireCooldownTime = if altFireInp then THROW_COOLDOWN else SWING_COOLDOWN
        updatePreFire = anyInput
        fireHoldTime = 0
    end

    self.fireLocked = fireCooldownTime > 0 or fireHoldTime > 0

    print(self.fireLocked)

    local newRotCFrame = CFrame.identity

    -- weapon fire logic
    if (self.fireLocked) then
        if (not currFireParams) then
            error("No fire params")
        end

        -- update weapon pre-fire
        if (updatePreFire) then
            if (currFireParams.altFire) then
                fireHoldTime += dt

                local spinSound = sounds[SOUND_IDS.SPIN] :: Sound
                if (not spinSound.IsPlaying) then
                    spinSound:Play()
                end

                local pastMinSpinTime = (fireHoldTime >= THROW_MINTIME)
                local littleUnderMinSpinTime = (fireHoldTime >= THROW_MINTIME - 0.2)
                local rotSpeedFac = pastMinSpinTime and FAST_SPIN_SOUND_SPEED or SLOW_SPIN_SOUND_SPEED
                local soundPBSpeed = pastMinSpinTime and FAST_SPIN_SPEED or SLOW_SPIN_SPEED

                spinSound.PlaybackSpeed = soundPBSpeed

                if (littleUnderMinSpinTime and not altFireInp) then
                    
                    local currPlaneVelMag = Vector3.new(
                        charPrimPart.AssemblyLinearVelocity.X, 0, charPrimPart.AssemblyLinearVelocity.Z
                    ).Magnitude

                    if (pastMinSpinTime) then
                        currFireParams.throwSpeed = 
                            math.max(BASE_THROW_SPEED, currPlaneVelMag * 0.5) + BONUS_THROW_SPEED
                    end

                    fireSignal = true
                    sounds[SOUND_IDS.LAUNCH]:Play()
                    spinSound:Stop()
                    fireHoldTime = 0
                end

                currSpinAng += dt * rotSpeedFac
                if (currSpinAng >= PI_2) then
                    currSpinAng = 0
                end
                newRotCFrame = CFrame.fromEulerAngles(currSpinAng, 0, 0)
            else
                fireSignal = true
            end 
        end

        -- fire weapon
        if (fireSignal) then
            print("HUZZAHHH")
            fireSignal, updatePreFire = false, false
            self:fire(charPrimPart.Position, camCFrame.LookVector.Unit, currFireParams)
        end
    end

    -- update root CFrame
    weapPrimPart.CFrame = WeaponCommon.dynOffset.apply(
        dt, currCharVel, camCFrame * CF_DEF_WEAP_OFFS
    ) * newRotCFrame

    if (not updatePreFire) then
        fireCooldownTime = math.max(fireCooldownTime - dt, 0)
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
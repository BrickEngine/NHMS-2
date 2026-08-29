--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local weaponsFolder = ReplicatedStorage.Shared.GameSystems.Weapons
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)
local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local WeaponCommon = require(ReplicatedStorage.Shared.GameSystems.Weapons.WeaponCommon)
local Global = require(ReplicatedStorage.Shared.Global)
local BaseWeapon = require(weaponsFolder.Arsenal.BaseWeapon)
local Schema = require(ReplicatedStorage.Shared.Util.Schema)
local Network = require(ReplicatedStorage.Shared.Network)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local ParticleEffects = require(ReplicatedStorage.Shared.Util.ParticleEffects)

-- client only modules
local InputManager
local CliApi

if (RunService:IsClient()) then
    InputManager = require(ReplicatedStorage.Shared.InputManager)
    CliApi = require(ReplicatedStorage.Shared.GameClient.CliNetApi)
end

------------------------------------------------------------------------------------------------------------------------

local CF_DEF_WEAP_OFFS = CFrame.new(Vector3.new(0.95, -1.4, -1.25)) 
local CF_DEF_BODY_WEAP_OFFS = CFrame.new(Vector3.new(1.3, 0.4, -2.25)) 
local CF_UNEQUIP_TARGET = CFrame.new(Vector3.new(0, -4, 0))

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
local SLASH_ANIM_SPEED = 1
local SLOW_SPIN_SOUND_SPEED = 20.5
local FAST_SPIN_SOUND_SPEED = 40
local SLOW_SPIN_SPEED = 3
local FAST_SPIN_SPEED = 4
local VEC2_SPARKS_SPREAD = Vector2.new(30,30)

local BASE_THROW_SPEED = 70
local BONUS_THROW_SPEED = 25

local SWING_SCAN_DIST = 15
local SWING_BASE_DAMAGE = 25

local ANIM_IDS = table.freeze({
    SWING = "rbxassetid://102246589048865",
    PARRY = "rbxassetid://127066524649533"
})

local SOUND_IDS = table.freeze({
    HIT = "rbxassetid://109675024264804",
    LAUNCH = "rbxassetid://112053896516106",
    SLICE = "rbxassetid://116173653232904",
    SPIN = "rbxassetid://138269694368715",
    HIT_FLESH_0 = "rbxassetid://96278024968375",
    HIT_FLESH_1 = "rbxassetid://134106511934613",
    HIT_FLESH_2 = "rbxassetid://106108068780898",
    HIT_BLOCK_0 = "rbxassetid://100159020945742",
    HIT_BLOCK_1 = "rbxassetid://107136980202866",
    LUNGE = "http://www.roblox.com/asset/?id=12222208",
    SLASH = "http://www.roblox.com/asset/?id=12222216",
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
    [SOUND_IDS.LUNGE] = {
        Volume = 0.6
    },
    [SOUND_IDS.SLASH] = {
        Volume = 0.7,
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.39, 9999)
    },
    [SOUND_IDS.HIT_FLESH_0] = {
        Volume = 1.5
    }
})

local PI_2 = math.pi * 2
local VEC3_UP = Vector3.new(0, 1, 0)

local localPlr = Players.LocalPlayer :: Player
local mdlFold = ReplicatedStorage.Assets.WeaponModels.Sword

local fireSignal = false
local updatePreFire = false
local fireHoldTime = 0
local fireCooldownTime = 0
local currSpinAng = 0 -- rad
local rechargeYOffs = 0

local equipUpdateConn: RBXScriptConnection
local unequipUpdateConn: RBXScriptConnection

export type SwordFireParams = {
    altFire: boolean,
    throwSpeed: number
}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local Sword = setmetatable({}, BaseWeapon)
Sword.__index = Sword

function Sword.new(uid: number, owner: Player?)
    local swordModel = mdlFold.ClassicSword:Clone()
    assert(swordModel.PrimaryPart, "Sword model does not have a primary part")

    swordModel.Parent = ReplicatedStorage
    for _, p: Instance in (swordModel:GetChildren()) do
        if (p:IsA("BasePart")) then
            p.Anchored = (p == swordModel.PrimaryPart) and true or false
        end
    end
    local attValString = owner and owner.Name or "None"
    swordModel:SetAttribute("Owner", attValString)

    local self: BaseWeapon.Weapon = BaseWeapon.new({
        uid = uid,
        name = WeaponName.SWORD,
        iconId = "rbxassetid://0",
        owner = owner or nil,
        fireSchema = {
            altFire = Schema.boolean(),
            throwSpeed = Schema.number()
        },
        weaponModel = swordModel,
        slot = 1
    })

    self.currFireParams = {
        altFire = false,
        throwSpeed = 0
    } :: SwordFireParams

    self.animationController = nil
    self.animator = nil
    self.animationTracks = {} :: {[string]: AnimationTrack}
    self.sounds = {} :: {[string]: Sound}
    
    if (RunService:IsClient()) then

        -- ensure character exists
        if (owner) then
            local char = owner.Character or owner.CharacterAdded:Wait()
            repeat task.wait() until char.PrimaryPart ~= nil 
        end

        if (owner and owner ~= localPlr) then
            local ownerChar = owner.Character
            WeaponCommon.weldWeaponModel(ownerChar, swordModel, CF_DEF_BODY_WEAP_OFFS)
        end

        -- anims
        local foundAnimController = swordModel:FindFirstChildWhichIsA("AnimationController")
        if (foundAnimController) then
            foundAnimController:Destroy()
        end

        -- init animations
        self.animationController = Instance.new("AnimationController", swordModel)
        self.animator = Instance.new("Animator", self.animationController)
        do
            assert(self.animationController, "No AnimationController instance")
            assert(self.animator, "No animator instance")

            for name: string, id: string in pairs(ANIM_IDS) do
                local newAnimation = Instance.new("Animation", self.animator)
                newAnimation.Name = name
                newAnimation.AnimationId = id

                local animTrack = self.animator:LoadAnimation(newAnimation)
                self.animationTracks[id] = animTrack
            end
        end

        -- sounds
        for _, soundId: string in pairs(SOUND_IDS) do
            local newSound = Instance.new("Sound", swordModel.PrimaryPart)
            newSound.SoundId = soundId

            if (SOUND_DATA[soundId]) then
                for prop: string, val: any in pairs(SOUND_DATA[soundId]) do
                    newSound[prop] = val
                end
            end
            self.sounds[soundId] = newSound
        end

        -- filter params and hit registering
        local sRayParams = RaycastParams.new()
        sRayParams.CollisionGroup = CollisionGroup.TRIGGER
        sRayParams.IgnoreWater = false
        sRayParams.RespectCanCollide = false
        sRayParams.ExcludeInstances = {}

        self.swordRayParams = sRayParams

        if (self.owner) then
            if (self.owner.Character) then
                self.swordRayParams.ExcludeInstances = self.owner.Character:GetChildren()
            end
            self.owner.CharacterAdded:Connect(function(newOwnerChar: Model)
                self.swordRayParams.ExcludeInstances = newOwnerChar:GetChildren()
            end)
        end
    end

    return setmetatable(self, Sword) :: any
end

function Sword:equip()
    if (not self.owner) then
        error("No weapon owner")
    end

    local weapModel: Model = self.weaponModel
    local ownerMdl: Model = self.owner.Character

    assert(weapModel.PrimaryPart, `Model '{weapModel}' has no primary part`)
    assert(ownerMdl.PrimaryPart, `Owner model '{ownerMdl}' has no primary part`)

    --WeaponCommon.joinWeaponToOwnerPrimPart(weapModel, ownerMdl)

    weapModel.Parent = Workspace:WaitForChild(Global.FOLDER_NAMES.WEAPONS_LOCAL)

    -------------------------------------------------------------------------------------
    -- only for other players
    if (not self:isOwnedByLocalPlr()) then
        return
    end

    -------------------------------------------------------------------------------------
    -- below here: everything that happens for weapon owner only
    print("EQUIPPING SWORD")

    if (unequipUpdateConn) then
        unequipUpdateConn:Disconnect()
    end

    local downPosOffsCFrame = CF_DEF_WEAP_OFFS * CF_UNEQUIP_TARGET
    local camCFrame = Workspace.CurrentCamera.CFrame
    local targetOffsLerpCFrame = downPosOffsCFrame
    local equipTime = 0

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

    local weapModel: Model = self.weaponModel
    local ownerChar: Model = self.owner.Character
    assert(weapModel.PrimaryPart, `Model '{weapModel}' has no primary part`)
    assert(ownerChar.PrimaryPart, `Owner model '{ownerChar}' has no primary part`)

    -------------------------------------------------------------------------------------
    -- only for other players
    if (not self:isOwnedByLocalPlr()) then
        weapModel.Parent = localPlr.Backpack
        return
    end

    -------------------------------------------------------------------------------------
    -- below here: everything that happens for weapon owner only
    print("UNEQUIPPING SWORD")

    if (equipUpdateConn) then
        equipUpdateConn:Disconnect()
    end

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

    for _, s: Sound in pairs(self.sounds) do
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
    local localPlrChar = localPlr.Character
    local localPlrPrimPart = localPlrChar.PrimaryPart

    if (self:isOwnedByLocalPlr()) then
        assert(localPlrChar, `Cannot fire own weapon '{self.name}' with missing character`)
        assert(localPlrPrimPart, `Missing character PrimaryPart`)

        -- only weapon owner can send fire event
        CliApi.events[Network.clientEvents.requestFireWeapon]:FireServer(pos, dir, fireParams)
    end
    
    -- fire logic for all clients
    -- regular swing logic
    if (not fireParams.altFire) then
        self.animationTracks[ANIM_IDS.SWING]:Play(0, 1, SWING_ANIM_SPEED)
        self.sounds[SOUND_IDS.SLASH]:Play()

        task.wait(0.2)

        local swingRay = Workspace:Raycast(pos - dir * 2, dir * SWING_SCAN_DIST, self.swordRayParams)
        if (swingRay :: RaycastResult) then
            local hitInst = swingRay.Instance
            local hitPos = swingRay.Position
            local hitNormal = swingRay.Normal

            -- water surface hits
            if (swingRay.Material == Enum.Material.Water) then
                ParticleEffects.summonWaterSplash(hitPos, VEC3_UP * 8, true)
                return
            end

            -- player hits
            if (hitInst.CollisionGroup == CollisionGroup.PLAYER) then
                local hitChar = hitInst.Parent

                if (hitChar:IsA("Model")) then
                    local hitPlr = Players:GetPlayerFromCharacter(hitChar)

                    -- only local player can fire a damage request
                    if (hitPlr and self:isOwnedByLocalPlr()) then
                        local plrVelMag = localPlrPrimPart.AssemblyLinearVelocity.Magnitude
                        local speedDmgBonus = math.min(plrVelMag * 0.05, 10)
                        local swingDmg = SWING_BASE_DAMAGE + speedDmgBonus

                        -- the char must be sent, since the remoteEvent expects an "entity" model
                        CliApi.events[Network.clientEvents.requestDamage]:FireServer(
                            hitChar, swingDmg, DamageType.BLADE
                        )
                    end
                end
                
                local rmdNum = math.random(0,2)
                local rdmSoundId = 
                    if (rmdNum == 0) then SOUND_IDS.HIT_FLESH_0 
                    elseif(rmdNum == 1) then SOUND_IDS.HIT_FLESH_1
                    else SOUND_IDS.HIT_FLESH_2

                self.sounds[rdmSoundId]:Play()
                ParticleEffects.summonBloodSplatter(pos)
                return
            end

            -- hitting anything else
            for _, track: AnimationTrack in pairs(self.animationTracks) do
                if (track.IsPlaying) then
                    track:Stop()
                end
            end
            self.animationTracks[ANIM_IDS.PARRY]:Play(0.5, 2, SLASH_ANIM_SPEED)

            ParticleEffects.summonSparks(hitPos + hitNormal * 0.5, -hitNormal * 4, VEC2_SPARKS_SPREAD)

            local rmdSoundId = math.random(0, 1) == 0 and SOUND_IDS.HIT_BLOCK_0 or SOUND_IDS.HIT_BLOCK_1
            self.sounds[rmdSoundId]:Play()
        end

    -- altfire logic (spin)
    else
        self.sounds[SOUND_IDS.LAUNCH]:Play()
    end
end

function Sword:onHit()
end

function Sword:reset()
    self.fireLocked = false
    updatePreFire = false
    fireCooldownTime = 0
    fireHoldTime = 0
    currSpinAng = 0
    rechargeYOffs = 0
end

function Sword:update(dt: number)
    if (not RunService:IsClient()) then
        error("cannot run on server")
    end

    -- do not update for other players
    if (not self:isOwnedByLocalPlr()) then
        return
    end

    local charMdl = self.owner.Character :: Model
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
        self.currFireParams = {
            altFire = altFireInp,
            throwSpeed = BASE_THROW_SPEED
        }
        fireCooldownTime = if altFireInp then THROW_COOLDOWN else SWING_COOLDOWN
        updatePreFire = anyInput
        fireHoldTime = 0
    end

    self.fireLocked = fireCooldownTime > 0 or fireHoldTime > 0

    local newRotCFrame = CFrame.identity

    -- weapon fire logic
    if (self.fireLocked) then
        if (not self.currFireParams) then
            error("No fire params")
        end

        -- update weapon pre-fire
        if (updatePreFire) then
            if (self.currFireParams.altFire) then
                fireHoldTime += dt

                local spinSound = self.sounds[SOUND_IDS.SPIN] :: Sound
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
                        self.currFireParams.throwSpeed = 
                            math.max(BASE_THROW_SPEED, currPlaneVelMag * 0.5) + BONUS_THROW_SPEED
                    end

                    fireSignal = true
                    self.sounds[SOUND_IDS.LAUNCH]:Play()
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
            if (self.currFireParams.altFire) then
                rechargeYOffs = -10
                newRotCFrame = CFrame.identity
            end
            fireSignal, updatePreFire = false, false
            self:fire(camCFrame.Position, camCFrame.LookVector.Unit, self.currFireParams)
        end
    end

    local rechargeCFrameOffs = CFrame.new(Vector3.new(0, rechargeYOffs, 0))
    rechargeYOffs = MathUtil.easeOutQuad(rechargeYOffs, 0, dt * 2)

    -- update root CFrame
    weapPrimPart.CFrame = WeaponCommon.dynOffset.apply(
        dt, currCharVel, camCFrame * CF_DEF_WEAP_OFFS
    ) * newRotCFrame * rechargeCFrameOffs



    if (not updatePreFire) then
        fireCooldownTime = math.max(fireCooldownTime - dt, 0)
    end
end

function Sword:destroy()
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
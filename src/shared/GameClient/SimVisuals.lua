--[[
    Manages visual effects and animations for local and global character instances.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterSounds = require(ReplicatedStorage.Shared.CharacterSounds)
local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local Animation = require(ReplicatedStorage.Shared.Util.Animation)
local FuncUtil = require(ReplicatedStorage.Shared.Util.FuncUtil)
local ParticleEffects = require(ReplicatedStorage.Shared.Util.ParticleEffects)

local ANIM_THRESHHOLD = 0.5 -- studs/s
local ANIM_SPEED_FAC = 0.025

local BASE_EFF_COOLDOWN_TIME = 0.2 -- cooldown time for most effects
local SPLASH_COOLDOWN_TIME = 0.25
local MIN_DIVE_SURFACE_TIME = 0.25 -- how much time to spend underwater before gasp

local preAnimConn = nil :: RBXScriptConnection?
local renderConn = nil :: RBXScriptConnection?
local soundConns = {} :: {RBXScriptConnection?}
local animConns = {} :: {RBXScriptConnection?}

local function disconnectConnTbl(tbl: {RBXScriptConnection?})
    if (tbl) then
        for _, conn: RBXScriptConnection? in pairs(tbl) do
            if (conn) then
                conn:Disconnect()
            end
        end
    end
end

type PlayerVars = {
    lastSimData: ClientRoot.SimData,
    offGroundTime: number,
    timeSinceSplash: number,
    submergedTime: number,
}


-- global additional player data for SimVisuals
playerVars = {} :: {[Player]: PlayerVars}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local SimVisuals = {
    localCharacter = Players.LocalPlayer.Character :: Model?,
    animation = nil :: any,

    DEFAULT_PLAYER_VARS = table.freeze({
        lastSimData = FuncUtil.deepCopy(ClientRoot.getDefaultSimData()),
        offGroundTime = 0,
        timeSinceSplash = 0,
        submergedTime = 0,
    }) :: PlayerVars
}

function SimVisuals.init()
    local function onCharAdded(character: Model)
        if (SimVisuals.animation) then
            SimVisuals.animation:destroy()
        end
        SimVisuals.localCharacter = character
        SimVisuals.animation = Animation.new(SimVisuals.localCharacter)

        if (preAnimConn) then preAnimConn:Disconnect() end
        preAnimConn = RunService.PreAnimation:Connect(SimVisuals.animUpdate)

        if (renderConn) then renderConn:Disconnect() end
        renderConn = RunService.RenderStepped:Connect(SimVisuals.update)

        --SimVisuals.resetEventSounds()
        SimVisuals.resetEventAnimations()
    end

    local function onCharRemoving(_: Model)
        if (preAnimConn) then
            preAnimConn:Disconnect()
        end
        if (renderConn) then
            renderConn:Disconnect()
        end
        disconnectConnTbl(soundConns)
        disconnectConnTbl(animConns)
        SimVisuals.removePlayerVars(Players.LocalPlayer)
    end

    local function onGlobalPlayerAdded(plr: Player)
        SimVisuals.createPlayerVars(plr)
    end

    local function onGlobalPlayerRemoving(plr: Player)
        SimVisuals.removePlayerVars(plr)
    end

    --------------------------------------------------------------------------------

    if (SimVisuals.localCharacter) then
        onCharAdded(SimVisuals.localCharacter)
    end
    Players.LocalPlayer.CharacterAdded:Connect(onCharAdded)
    Players.LocalPlayer.CharacterRemoving:Connect(onCharRemoving)

    for _, plr: Player in (Players:GetPlayers()) do
        onGlobalPlayerAdded(plr)
    end
    Players.PlayerAdded:Connect(function(plr: Player)
        onGlobalPlayerAdded(plr)
    end)
    Players.PlayerRemoving:Connect(function(plr: Player, _: Enum.PlayerExitReason)
        onGlobalPlayerRemoving(plr)
    end)
end

------------------------------------------------------------------------------------------------------------------------

function SimVisuals.createPlayerVars(plr: Player)
    if (playerVars[plr]) then
        warn(`'{plr}' already has playerVars data`)
    end
    playerVars[plr] = FuncUtil.deepCopy(SimVisuals.DEFAULT_PLAYER_VARS)
end

function SimVisuals.removePlayerVars(plr: Player)
    if (not playerVars[plr]) then
        warn(`'{plr}' does not have a playerVars entry`); return
    end
    playerVars[plr] = nil
end

--[[
    Main function for updating local and global player sounds and visuals
    @param plr - player for which to update
]]
function SimVisuals.updatePlayerEffects(dt: number, plr: Player)
    local function copySimData(newSD: ClientRoot.SimData, prevSD: ClientRoot.SimData)
        for i: string, v in pairs(newSD) do
            prevSD[i] = v
        end
    end

    local function updateGroundEffects(newSD: ClientRoot.SimData, prevSD: ClientRoot.SimData)
        local offGroundTime = playerVars[plr].offGroundTime
        if (newSD.playerStateId ~= PlayerStateId.GROUND) then
            return
        end
        
        if (newSD.isGrounded and offGroundTime >= BASE_EFF_COOLDOWN_TIME) then
            CharacterSounds:updatePlayerSound(plr, CharacterSounds.SOUND_ITEMS.FLOOR_HIT, true)
        end

        if (not newSD.isGrounded) then
            offGroundTime += dt
        else
            offGroundTime = 0
        end
        playerVars[plr].offGroundTime = offGroundTime
    end

    local function updateWaterEffects(char: Model, newSD: ClientRoot.SimData, prevSD: ClientRoot.SimData)
        local splashTime = playerVars[plr].timeSinceSplash
        local submergedTime = playerVars[plr].submergedTime
        if (newSD.playerStateId ~= PlayerStateId.WATER) then
            --return
        end
        if (not char.PrimaryPart) then
            error(`missing primary part of '{plr}'`)
        end

        -- entering and leaving surface
        local charVel = char.PrimaryPart.AssemblyLinearVelocity
        if (newSD.inWater and (not prevSD.inWater or prevSD.playerStateId == PlayerStateId.GROUND)) then
            if (splashTime <= 0 and charVel.Magnitude > 5) then
                CharacterSounds:updatePlayerSound(plr, CharacterSounds.SOUND_ITEMS.WATER_SPLASH, true)
                ParticleEffects.summonWaterSplash(
                    char.PrimaryPart.Position - charVel.Unit * 0.5, 
                    char.PrimaryPart.AssemblyLinearVelocity
                )
                splashTime = SPLASH_COOLDOWN_TIME --/ splashVelFac
            end
        end

        -- diving and surfacing
        if (newSD.inWater and (newSD.onWaterSurface ~= prevSD.onWaterSurface)) then
            if (newSD.onWaterSurface) then
                if (submergedTime > MIN_DIVE_SURFACE_TIME) then
                    CharacterSounds:updatePlayerSound(plr, CharacterSounds.SOUND_ITEMS.WATER_SURFACE, true)
                end
            else
                if (plr == Players.LocalPlayer) then
                    CharacterSounds:updateLocalSound(CharacterSounds.SOUND_ITEMS.WATER_DIVE, true)
                end
            end
        end

                print(submergedTime)

        if (not newSD.onWaterSurface) then
            submergedTime += dt
        else
            submergedTime = 0
        end

        local splashVelFac = math.clamp(charVel.Magnitude * 0.03, 0.6, 1.75)
        splashTime -= dt * splashVelFac
        if (splashTime < 0) then
            splashTime = 0
        end

        playerVars[plr].timeSinceSplash = splashTime
        playerVars[plr].submergedTime = submergedTime
    end

    local char = plr.Character
    if (not char or not char.PrimaryPart) then
        return
    end
    if (not playerVars[plr]) then
        error(`No existing playerVars entry for '{plr}'`)
    end

    do
        local simData: ClientRoot.SimData = ClientRoot.getSimDataOfPlayer(plr)
        local prevSimData: ClientRoot.SimData = playerVars[plr].lastSimData

        if (simData.playerStateId == PlayerStateId.NONE) then
            return
        end

        updateGroundEffects(simData, prevSimData)
        updateWaterEffects(char, simData, prevSimData)

        copySimData(simData, prevSimData)
    end
end

function SimVisuals.resetEventAnimations()
    local anim = SimVisuals.animation

    disconnectConnTbl(animConns)
    animConns = {
        ClientRoot.signals.deathStateChanged.Event:Connect(function(died: boolean, lastDmgType: string)
            if (died) then
                anim:setState(Animation.AnimationStateId.DEATH, 0.2)
                anim:adjustSpeed(1.5)
            end
        end)
    }
end

function SimVisuals.updateAnimations()
    local simData = ClientRoot.getSimData()
    local plrData = ClientRoot.getPlayerData()

    if (not (SimVisuals.localCharacter and simData and plrData)) then
        return
    end

    local charPrimPart = SimVisuals.localCharacter.PrimaryPart
    local anim = SimVisuals.animation
    if (not charPrimPart) then
        warn("Missing PimraryPart of character"); return
    end

    local horiVelVec = Vector3.new(charPrimPart.AssemblyLinearVelocity.X, 0 ,charPrimPart.AssemblyLinearVelocity.Z)

    if (plrData.isDead) then
        return
    end

    if (simData.isGrounded) then
        if (horiVelVec.Magnitude > ANIM_THRESHHOLD) then
            anim:setState(Animation.AnimationStateId.WALK)
            anim:adjustSpeed(horiVelVec.Magnitude * ANIM_SPEED_FAC)
        else
            anim:setState(Animation.AnimationStateId.IDLE)
            anim:adjustSpeed(1)
        end
    elseif (simData.inWater) then
        anim:setState(Animation.AnimationStateId.WALK)
        anim:adjustSpeed(1)
    else
        anim:setState(Animation.AnimationStateId.IDLE)
        anim:adjustSpeed(1)
    end
end

------------------------------------------------------------------------------------------------------------------------

function SimVisuals.animUpdate(dt: number)
    SimVisuals.updateAnimations()
end

function SimVisuals.update(dt: number)
    for plr: Player, _ in pairs(playerVars) do
        SimVisuals.updatePlayerEffects(dt, plr)
    end
end

return SimVisuals
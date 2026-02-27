--[[
    Sound manager module.

    Creates predefined sound instances for each player and plays them across the 
    server-client boundary for other players.
    This module is meant to be used client-side only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Network = require(ReplicatedStorage.Shared.Network)
local CliNetApi = require(ReplicatedStorage.Shared.GameClient.CliNetApi)

local SOUND_PB_REG_HUGE = 100

local SOUND_ITEMS = table.freeze({
    JUMP = "JumpSound",
    FLOOR_HIT = "FloorHitSound",
    DAMAGE = "DamageSound",
    WATER_SPLASH = "WaterSplashSound",
    WATER_MOVEMENT = "WaterMovementSound",
    WALL_ENTER_0 = "WallEnter0Sound",
    WALL_ENTER_1 = "WallEnter1Sound",
    WALL_SLIDE = "WallSlideSound",
})

local SOUND_DATA = table.freeze({
    [SOUND_ITEMS.DAMAGE] = {
        SoundId = "rbxassetid://5466166437", --5466166437
    },
    [SOUND_ITEMS.JUMP] = {
        SoundId = "rbxassetid://143384769", --5466166437 86604727900745 143384769 128602720222961
        Volume = 0.5,
    },
    [SOUND_ITEMS.FLOOR_HIT] = {
        SoundId = "rbxassetid://127822240770734", --135370882594044
        Volume = 1.2,
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0, 0.15)
    },
    [SOUND_ITEMS.WATER_SPLASH] = {
        SoundId = "rbxassetid://72842661683082",
    },
    [SOUND_ITEMS.WATER_MOVEMENT] = {
        SoundId = "rbxassetid://5466166437",
    },
    [SOUND_ITEMS.WALL_ENTER_0] = {
        SoundId = "rbxassetid://15764092592",
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.1, SOUND_PB_REG_HUGE) --0.1
    },
    [SOUND_ITEMS.WALL_ENTER_1] = {
        SoundId = "rbxassetid://81202220081219",
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.1, SOUND_PB_REG_HUGE)
    },
    [SOUND_ITEMS.WALL_SLIDE] = {
        SoundId = "rbxassetid://81521378859476",
        Looped = true
    },
})

local soundEffectsMap = {} :: {[Sound]: {SoundEffect}}
local playerSoundsMap = {} :: {[Player]: {[string]: Sound}}
local playerConnTbl = {} :: {[Player]: {RBXScriptConnection}}

local localPlr = Players.LocalPlayer

------------------------------------------------------------------------------------------------------------------------

-- Creates a sound instance that is parented to a player's primary part, maps sound item to player
local function createSounds(plr: Player, char: Model, item: string)
    local primaryPart = char.PrimaryPart
    assert(primaryPart, `Missing primary part of '{plr.Name}'`)

    local sound = Instance.new("Sound", primaryPart)
    sound.Name = item

    -- set all predefined sound properties
    for propName: string, propVal: any in pairs(SOUND_DATA[item]) do
        sound[propName] = propVal
    end

    -- map sound item to player
    if (not playerSoundsMap[plr]) then
        playerSoundsMap[plr] = {}
    end
    playerSoundsMap[plr][item] = sound
end

local function resetSound(sound: Sound)
    sound:Stop()
    sound:Play()
end

local function updateSound(sound: Sound, play: boolean)
    if (not play) then
        if (sound.IsPlaying) then
            sound:Stop()
        end
        sound.TimePosition = 0
        return
    end
    if (sound.Looped) then
        if (sound.IsPlaying) then
            return
        end
        resetSound(sound)
    else
        if (play) then
            resetSound(sound)
        end
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local SoundManager = {
    SOUND_ITEMS = SOUND_ITEMS
}

function SoundManager.init()
    if (not RunService:IsClient()) then
        error("Soundmanager should be initialized client-side only")
    end

    local function addPlrSounds(plr: Player, char: Model)
        for _, soundName: string in pairs(SOUND_ITEMS) do
            createSounds(plr, char, soundName)
        end
    end

    local function clearPlrSounds(plr: Player)
        if (not playerSoundsMap[plr]) then
            return
        end
        for _, sound: Sound in pairs(playerSoundsMap[plr]) do
            sound:Destroy()
        end
        playerSoundsMap[plr] = nil
    end

    local function onPlayerAdded(plr: Player)
        local charAddedConn = plr.CharacterAdded:Connect(function(char: Model) addPlrSounds(plr, char) end)
        local charRemConn = plr.CharacterRemoving:Connect(function(char: Model) clearPlrSounds(plr) end)
        playerConnTbl[plr] = {charAddedConn, charRemConn}
    end

    local function onPlayerRemoving(plr: Player)
        if (playerConnTbl[plr]) then
            for _, c: RBXScriptConnection in pairs(playerConnTbl[plr]) do
                c:Disconnect()
            end
            playerConnTbl[plr] = nil
        end
        clearPlrSounds(plr)
    end

    ---------------------------------

    -- in case init was called before
    if (playerConnTbl) then
        for plr: Player, _ in pairs(playerConnTbl) do
            for _, c: RBXScriptConnection in pairs(playerConnTbl[plr]) do
                c:Disconnect()
            end
        end
    end
    playerConnTbl = {}

    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    -- add sounds for existing players
    for _, plr: Player in pairs(Players:GetPlayers()) do
        onPlayerAdded(plr)
        local char = plr.Character
        if (char and char.PrimaryPart) then
            addPlrSounds(plr, char)
        end
    end
end

------------------------------------------------------------------------------------------------------------------------

-- Updates the specified sound item of another player
function SoundManager:updatePlayerSound(plr: Player, item: string, play: boolean)
    if (plr == localPlr) then 
        return 
    end
    if (not (playerSoundsMap[plr] and playerSoundsMap[plr][item])) then
        warn("No sound"); return
    end
    updateSound(playerSoundsMap[plr][item], play)
end

-- Plays the specified sound item locally
function SoundManager:updateLocal(item: string, play: boolean)
    local sound = playerSoundsMap[localPlr][item]
    if (not sound) then error(`Nonexisten sound for '{item}'`) end

    updateSound(sound, play)
end

function SoundManager:updateGlobalSound(item: string, play: boolean)
    self:updateLocal(item, play)
    CliNetApi.events[Network.clientEvents.requestSound]:FireServer(item, play)
end

function SoundManager:addSoundEffects(sound: Sound, effects: {SoundEffect})
    local tbl = soundEffectsMap[sound] and soundEffectsMap[sound] or {}
    for _, eff: SoundEffect in pairs(effects) do
        eff.Parent = sound
        eff.Enabled = true
        table.insert(tbl, eff)
    end
    soundEffectsMap[sound] = tbl
end

function SoundManager:clearAllEffects(sound: Sound)
    local tbl = soundEffectsMap[sound]
    if (tbl) then
        for _, e: SoundEffect in pairs(tbl) do
            e:Destroy()
        end 
    end
    soundEffectsMap[sound] = nil
end

if (RunService:IsClient()) then
    SoundManager.init()
end

return SoundManager
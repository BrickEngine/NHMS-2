--[[
    Sound manager module.

    Creates predefined sound instances for each player and plays them across the 
    server-client boundary for other players.
    This module is meant to be used client-side only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage.Shared.Network)
local CliNetApi = require(ReplicatedStorage.Shared.GameClient.CliNetApi)

local SOUND_PB_REG_HUGE = 100
local PLAY_LOCAL = true -- whether to play non-looped sounds for the client locally
--local SOUND_POOL_SIZE = 3 -- number of instances to create for each sound

local SOUND_ITEMS = table.freeze({
    JUMP = "JumpSound",
    FLOOR_HIT = "FloorHitSound",
    DAMAGE_0 = "Damage0Sound",
    DAMAGE_1 = "Damage1Sound",
    DAMAGE_2 = "Damage2Sound",
    DEATH = "DeathSound",
    DEATH_DROWN = "DeathDrownSound",
    DEATH_FALL = "DeathFallSound",
    WATER_SPLASH = "WaterSplashSound",
    WATER_MOVEMENT = "WaterMovementSound",
    WATER_DIVE = "WaterDiveSound",
    WATER_SURFACE = "WaterSurfaceSound",
    WALL_ENTER_0 = "WallEnter0Sound",
    WALL_ENTER_1 = "WallEnter1Sound",
    WALL_SLIDE = "WallSlideSound",
})

local SOUND_DATA = table.freeze({
    [SOUND_ITEMS.DAMAGE_0] = { -- "yuauuu"
        SoundId = "rbxassetid://135514575451369",
        Volume = 0.8,
    },
    [SOUND_ITEMS.DAMAGE_1] = { -- "haaa"
        SoundId = "rbxassetid://97084250180421",
        Volume = 0.8,
    },
    [SOUND_ITEMS.DAMAGE_2] = { -- "uuuiii"
        SoundId = "rbxassetid://76277846903686",
        Volume = 0.8,
    },
    [SOUND_ITEMS.DEATH] = {
        SoundId = "rbxassetid://98940142026447",
        Volume = 0.9,
    },
    [SOUND_ITEMS.DEATH_DROWN] = {
        SoundId = "rbxassetid://134069985010030",
    },
    [SOUND_ITEMS.DEATH_FALL] = {
        SoundId = "rbxassetid://105918113497097", --125793119459513 95272958949487
        Volume = 0.9,
    },
    [SOUND_ITEMS.JUMP] = {
        SoundId = "rbxassetid://143384769", --5466166437 86604727900745 143384769 128602720222961
        Volume = 1.2,
    },
    [SOUND_ITEMS.FLOOR_HIT] = {
        SoundId = "rbxassetid://127822240770734", --135370882594044
        Volume = 1.2,
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0, 0.15)
    },
    [SOUND_ITEMS.WATER_SPLASH] = {
        SoundId = "rbxassetid://72842661683082",
        Volume = 1.08,
        PlaybackSpeed = 2,
    },
    [SOUND_ITEMS.WATER_MOVEMENT] = {
        SoundId = "rbxassetid://5466166437",
        Looped = true,
    },
    [SOUND_ITEMS.WATER_DIVE] = {
        SoundId = "rbxassetid://96244940601143",
        Volume = 0.375,
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.62, 2),
        PlaybackSpeed = 1.25
    },
    [SOUND_ITEMS.WATER_SURFACE] = {
        SoundId = "rbxassetid://9114555843",
    },
    [SOUND_ITEMS.WALL_ENTER_0] = {
        SoundId = "rbxassetid://81202220081219",
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.1, SOUND_PB_REG_HUGE) --0.1
    },
    [SOUND_ITEMS.WALL_ENTER_1] = {
        SoundId = "rbxassetid://81202220081219", --15764092592
        PlaybackRegionsEnabled = true,
        PlaybackRegion = NumberRange.new(0.1, SOUND_PB_REG_HUGE)
    },
    [SOUND_ITEMS.WALL_SLIDE] = {
        SoundId = "rbxassetid://81521378859476", --81521378859476 --140484482380066 --9125636618
        --PlaybackRegionsEnabled = true,
        Volume = 1,
        --PlaybackRegion = NumberRange.new(12, 14),
        Looped = true
    },
})

--sensory: 1837629716
--plasma: 140301279229381

local soundEffectsMap = {} :: {[Sound]: {SoundEffect}}
local playerSoundsMap = {} :: {[Player]: {[string]: Sound}}
local playerConnTbl = {} :: {[Player]: {RBXScriptConnection}}

local localPlr = Players.LocalPlayer

------------------------------------------------------------------------------------------------------------------------

-- Creates a sound instance that is parented to a player's primary part, maps sound item to player
local function createSound(plr: Player, char: Model, item: string)
    local primaryPart = char.PrimaryPart
    assert(primaryPart, `Missing primary part of '{plr.Name}'`)

    local sound = Instance.new("Sound")
    sound.Name = item

    -- set all predefined sound properties and parent
    for propName: string, propVal: any in pairs(SOUND_DATA[item]) do
        sound[propName] = propVal
    end

    -- set sound parent
    if (plr == localPlr) then
        sound.Parent = Workspace.CurrentCamera
    else
        sound.Parent = primaryPart
    end

    -- map sound item to player
    if (not playerSoundsMap[plr]) then
        playerSoundsMap[plr] = {}
    end
    playerSoundsMap[plr][item] = sound
end

-- Updates looped and non-looped 3D-Sounds
local function updateSound(sound: Sound, play: boolean)
    local function resetSound(sound: Sound)
        sound:Stop()
        sound:Play()
    end

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

local function playLocalSound(sound: Sound, play: boolean)
    if (play) then
        SoundService:PlayLocalSound(sound)
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
            createSound(plr, char, soundName)
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

-- Plays the specified sound item for (on) the local player
function SoundManager:updateLocal(item: string, play: boolean)
    local sound = playerSoundsMap[localPlr][item]
    if (not sound) then error(`Nonexistent sound for '{item}'`) end

    if (PLAY_LOCAL) then
        if (sound.Looped) then
            updateSound(sound, play)
        else
            playLocalSound(sound, play)
        end
    else
        updateSound(sound, play)
    end
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
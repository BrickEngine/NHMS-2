local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Global = require(ReplicatedStorage.Shared.Global)
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local Network = require(ReplicatedStorage.Shared.Network)
local ServNetApi = require(script.ServNetApi)

local DEATH_TIME_BUFFER = 2.0
local DEATH_EVENT_COOLDOWN = 3.0

local deathCooldownList = {} :: {[Player]: number}

------------------------------------------------------------------------------------------------------
-- Initialize Workspace
do
    -- Create Workspace folder for runtime player characters
    if (not Workspace:FindFirstChild(Global.PLAYERS_INST_FOLDER_NAME)) then
        Instance.new(
            "Folder", Workspace
        ).Name = Global.PLAYERS_INST_FOLDER_NAME
    end

    -- Check if all collision groups are registered
    for _, groupName in pairs(CollisionGroup) do
        if (not PhysicsService:IsCollisionGroupRegistered(groupName)) then
            warn("Unregistered collision group: " .. groupName)
        end
    end

    -- Init walls
    local wallsFold = Workspace:FindFirstChild(Global.WALL_INST_FOLDER_NAME, true)
    if (wallsFold) then
        for _, v: Instance in pairs(wallsFold:GetDescendants()) do
            if (v:IsA("BasePart")) then
                v.CollisionGroup = CollisionGroup.WALL
            end
        end
    else
        warn("No 'Walls' folder present")
    end
end

------------------------------------------------------------------------------------------------------------------------

local function removePlayerCharacter(plr: Player)
	if (plr.Character) then
        plr.Character:Destroy() 
        plr.Character = nil
    end
end

local function revivePlayer(plr: Player)
    local currData = PlayerData.getPlayerData(plr)
    currData.health = PlayerData.LIMITS.health
    currData.isDead = false

    ServNetApi.events[Network.serverEvents.setHealth]:FireAllClients(plr, currData.health)
end

local function spawnPlayer(plr: Player)
    if (plr.Character) then
        warn(plr.Name.." attempted to spawn with active character")
        plr.Character:Destroy()
    end
    -- TODO: proper PlayerModel selection
    local plrMdl = StarterPlayer:FindFirstChild("Playermodel")
	local newCharacter = CharacterDef.createCharacter(plrMdl)

    -- TODO: proper spawn management
    local tmpSpawn : SpawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local spawnPos : Vector3 = (tmpSpawn.CFrame.Position + Vector3.new(0,2,0)) or Vector3.new(0, 50, 0)
    do
        newCharacter.Name = tostring(plr.UserId)
        newCharacter.Parent = Workspace:FindFirstChild(Global.PLAYERS_INST_FOLDER_NAME)
        newCharacter:MoveTo(spawnPos)

        plr.Character = newCharacter
        newCharacter.PrimaryPart:SetNetworkOwner(plr)
    end

    assert(plr.Character and plr.Character.PrimaryPart, "Player character must exist and have a primary part")

    if (Workspace.StreamingEnabled) then
        plr.ReplicationFocus = plr.Character.PrimaryPart
    end

    revivePlayer(plr)

	return newCharacter
end

local function killPlayer(plr: Player)
    local plrData = PlayerData.getPlayerData(plr)

    if (plrData.health ~= 0) then
        plrData.health = 0
        ServNetApi.events[Network.serverEvents.setHealth]:FireAllClients(plr, 0)
    end
    plrData.isDead = true
    task.wait(DEATH_TIME_BUFFER)
    removePlayerCharacter(plr)

    -- client can only spawn after characterRemoving fired and spawn is requested
    --removePlayerCharacter(plr)
    --spawnPlayer(plr)
end

local function changePlrHealth(plr: Player, newHealth: number, damageType: string, addBonus: boolean?)
    local currPlrData = PlayerData.getPlayerData(plr)
    local limit = PlayerData.LIMITS.health
    if (addBonus) then
        limit = PlayerData.LIMITS.healthWithBonus
    end
    currPlrData.lastDamageType = damageType
    currPlrData.health = newHealth
    math.clamp(currPlrData.health, 0, limit)

    ServNetApi.events[Network.serverEvents.setHealth]:FireAllClients(plr, currPlrData.health, damageType)

    print(`Server HP of {plr}: {currPlrData.health}`)
    if (currPlrData.health <= 0) then
        killPlayer(plr)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Event methods

local function onPlayerRequestSound(plr: Player, item: string?, play: boolean?)
    if (type(item) ~= "string" or type(play) ~= "boolean") then
        warn(`{plr.Name} sent illegal sound item arg`); return
    end
    ServNetApi.events[Network.serverEvents.playSound]:FireAllClients(plr, item, play)
end

-- Changes player health, if the requested value is int
local function onPlayerRequestChangeHealth(plr: Player, newHp: number?, damageType: string?)
    if (type(newHp) ~= "number") then
        warn("not a number"); return
    end
    local _damageType = DamageType.NONE
    if (damageType) then
        if (
            damageType == DamageType.FALL
            or damageType == DamageType.DROWN
            or DamageType == DamageType.EXPLOSION
        ) then
            _damageType = damageType
        end
        print(_damageType)
    end
    if (newHp % 1 == 0) then
        changePlrHealth(plr, newHp, _damageType)
    end
end

local function onPlayerRequestSpawn(plr: Player)
    if (deathCooldownList[plr] > 0) then
        warn(`{plr} on cooldown`); return
    end

    spawnPlayer(plr)

    deathCooldownList[plr] = DEATH_EVENT_COOLDOWN
end

-- network events management
local remEventFunctions = {
    [Network.clientEvents.requestSpawn] = function(plr: Player)
        onPlayerRequestSpawn(plr)
    end,
    [Network.clientEvents.requestDespawn] = function(plr: Player)
        removePlayerCharacter(plr)
    end,
    [Network.clientEvents.requestSound] = function(plr: Player, ...)
        onPlayerRequestSound(plr, ...)
    end,
    [Network.clientEvents.requestChangeHealth] = function(plr: Player, ...)
        onPlayerRequestChangeHealth(plr, ...)
    end,
    [Network.clientEvents.requestWeaponFire] = function(plr: Player, ...)
        -- TODO
    end,
    [Network.clientEvents.requestWeaponSwitch] = function(plr: Player, ...)
        -- TODO
    end,
}

local fastRemEventFunctions = {
    [Network.clientFastEvents.jointsDataToServer] = function(plr: Player)
        -- TODO
    end,
    [Network.clientFastEvents.plrDataToServer] = function(plr: Player)
        -- TODO
    end,
}

local remFunctionFunctions = {}

ServNetApi.implementREvents(remEventFunctions)
ServNetApi.implementFastREvents(fastRemEventFunctions)
ServNetApi.implementRFunctions(remFunctionFunctions)

------------------------------------------------------------------------------------------------------------------------

local function onPlayerAdded(plr: Player)
    print(plr.Name .. " joined the game")
    deathCooldownList[plr] = 0
    PlayerData.createPlayerData(plr)
end

local function onPlayerRemoving(plr: Player)
    print(plr.Name .. " left the game")
    deathCooldownList[plr] = nil
    PlayerData.removePlayerData(plr)

    removePlayerCharacter(plr)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- action loop [20 Hz]
local loopDt = 0.05
while (task.wait(loopDt)) do
    -- decrement cooldown timers
    for plr: Player, c: number in pairs(deathCooldownList) do
        if (deathCooldownList[plr]) then
            local newTime = c - loopDt
            if (newTime < 0 ) then
                newTime = 0
            end
            deathCooldownList[plr] = newTime
        end
    end
end

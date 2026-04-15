local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Global = require(ReplicatedStorage.Shared.Global)
local ServerRoot = require(ServerScriptService.ServerRoot)
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)
local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)
local WeaponName = require(ReplicatedStorage.Shared.Enums.WeaponName)
local WeaponManager = require(ReplicatedStorage.Shared.GameSystems.Weapons.WeaponManager)
local Network = require(ReplicatedStorage.Shared.Network)
local ServNetApi = require(script.ServNetApi)

local LOOP_DT = 0.05
local DEATH_REMOVE_DELAY = 2.0
local DEATH_EVENT_COOLDOWN = 3.0

local VALID_CLIENT_DAMAGE_TYPES = {
    [DamageType.FALL] = true,
    [DamageType.NAPALM] = true,
    [DamageType.EXPLOSION] = true,
    [DamageType.DROWN] = true
}

local deathCooldownList = {} :: {[Player]: number}

------------------------------------------------------------------------------------------------------------------------
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
-- Game table
------------------------------------------------------------------------------------------------------------------------
local Game = {}
Game.__index = Game

function Game.removePlayerCharacter(plr: Player)
	if (plr.Character) then
        plr.Character:Destroy() 
        plr.Character = nil
    end
end

function Game.revivePlayer(plr: Player)
    ServerRoot.fullyHealPlayer(plr)
    deathCooldownList[plr] = DEATH_EVENT_COOLDOWN
end

function Game.spawnPlayer(plr: Player)
    if (plr.Character) then
        warn(plr.Name.." attempted to spawn with active character")
        Game.removePlayerCharacter(plr)
        --return
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

        newCharacter.PrimaryPart:SetNetworkOwner(plr)
        plr.Character = newCharacter
    end

    assert(plr.Character and plr.Character.PrimaryPart, "Player character must exist and have a primary part")

    if (Workspace.StreamingEnabled) then
        plr.ReplicationFocus = plr.Character.PrimaryPart
    end

    Game.revivePlayer(plr)

	return newCharacter
end

function Game.removeWeaponFromPlayerInventory(plr: Player, slot: number)
    local plrData = ServerRoot.getPlayerData(plr)
    if (not plrData.inventory[slot]) then
        error(`No existing weapon in {plr}'s inventory at slot {slot}`)
    end

    plrData.inventory[slot]:destroy()
    plrData.inventory[slot] = nil
end

-- Adds a new weapon to the player's inventory, or overwrites an occupied inventory slot
function Game.addWeaponToPlayerInventory(plr: Player, weapName: string)
    local newWeapObj, weapId = WeaponManager.createWeapon(plr.Character, weapName)
    local weapSlot = newWeapObj.slot
    local plrData = ServerRoot.getPlayerData(plr)

    if (plrData.inventory[weapSlot]) then
        plrData.inventory[weapSlot]:destroy()
        plrData.inventory[weapSlot] = nil
    end
    plrData.inventory[weapSlot] = newWeapObj

    ServNetApi.events[Network.serverEvents.createWeapon]:FireAllClients(plr, weapName, weapId)
end

function Game.equipPlayerStaterGear(plr: Player)
    Game.addWeaponToPlayerInventory(plr, WeaponName.SWORD)
end

------------------------------------------------------------------------------------------------------------------------
-- Network
------------------------------------------------------------------------------------------------------------------------
-- Event methods

local function onPlayerRequestSpawn(plr: Player)
    if (deathCooldownList[plr] > 0) then
        warn(`{plr} on cooldown`); return
    end
    Game.spawnPlayer(plr)
    Game.equipPlayerStaterGear(plr)
end

local function onPlayerRequestDespawn(plr: Player)
    Game.removePlayerCharacter(plr)
end

local function onPlayerRequestSound(plr: Player, item: string?, play: boolean?)
    if (type(item) ~= "string" or type(play) ~= "boolean") then
        warn(`{plr.Name} sent illegal sound item arg`); return
    end
    ServNetApi.events[Network.serverEvents.playSound]:FireAllClients(plr, item, play)
end

-- Changes player health, if the requested value is int
local function onPlayerRequestChangeHealth(plr: Player, newHp: number?, damageType: string?)
    local currHp = ServerRoot.getPlayerData(plr).health
    if (type(newHp) ~= "number") then 
        warn(`{plr} sent invalid newHp parameter`); return 
    end
    -- players can only request health reduction
    if (newHp % 1 ~= 0 or newHp > currHp) then 
        warn(`{plr} sent incorrect newHp format`); return 
    end
    if (not (damageType and VALID_CLIENT_DAMAGE_TYPES[damageType])) then
        print(VALID_CLIENT_DAMAGE_TYPES[damageType])
        warn("Invalid damage type"); return
    end

    --changePlrHealth(plr, newHp, _damageType)
    ServerRoot.changePlrHealth(plr, newHp, damageType)
end

local function onPlayerRequestActiveWeaponSwitch(plr: Player, newSlot: number?)
    local plrData = ServerRoot.getPlayerData(plr)
    if (typeof(newSlot) ~= "number") then
        warn(`{plr} sent invalid newSlot parameter`); return
    end
    if (plrData.activeInvSlot == newSlot) then
        warn(`{plr} already has slot {newSlot} active`); return
    end
    
    local invSlotWeapon = plrData.inventory[newSlot]
    if (not invSlotWeapon) then
        warn(`{plr} has no weapon in slot {newSlot}`); return
    end
    plrData.activeInvSlot = newSlot
end

local function onPlayerRequestWeaponFire(plr: Player)
    local plrData = ServerRoot.getPlayerData(plr)
    local targetWeapon = plrData.inventory[plrData.activeInvSlot]
    local targetWeaponName = targetWeapon.name

    if (not targetWeapon) then
        warn(`{plr} has no weapon in active slot {plrData.activeInvSlot}`)
    end
    ServNetApi.events[Network.serverEvents.fireWeapon]:FireAllClients(plr, targetWeaponName)
end

local remEventFunctions = {
    [Network.clientEvents.requestSpawn] = function(plr: Player)
        onPlayerRequestSpawn(plr)
    end,
    [Network.clientEvents.requestDespawn] = function(plr: Player)
        onPlayerRequestDespawn(plr)
    end,
    [Network.clientEvents.requestSound] = function(plr: Player, ...)
        onPlayerRequestSound(plr, ...)
    end,
    [Network.clientEvents.requestChangeHealth] = function(plr: Player, ...)
        onPlayerRequestChangeHealth(plr, ...)
    end,
    [Network.clientEvents.requestWeaponFire] = function(plr: Player)
        onPlayerRequestWeaponFire(plr)
    end,
    [Network.clientEvents.requestActiveWeaponSwitch] = function(plr: Player, ...)
        onPlayerRequestActiveWeaponSwitch(plr, ...)
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
-- Bindable events (signals)

local function onPlayerDied(plr: Player)
    task.wait(DEATH_REMOVE_DELAY)
    Game.removePlayerCharacter(plr)
end

ServerRoot.signals.playerDied.Event:Connect(onPlayerDied)

------------------------------------------------------------------------------------------------------------------------
-- Connections

local function onPlayerAdded(plr: Player)
    print(plr.Name .. " joined the game")
    deathCooldownList[plr] = 0
    ServerRoot.createPlayerData(plr)
end

local function onPlayerRemoving(plr: Player)
    print(plr.Name .. " left the game")
    deathCooldownList[plr] = nil
    ServerRoot.removePlayerData(plr)

    Game.removePlayerCharacter(plr)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- action loop [20 Hz]
while (task.wait(LOOP_DT)) do
    -- decrement cooldown timers
    for plr: Player, c: number in pairs(deathCooldownList) do
        if (deathCooldownList[plr]) then
            local newTime = c - LOOP_DT
            if (newTime < 0 ) then
                newTime = 0
            end
            deathCooldownList[plr] = newTime
        end
    end
end
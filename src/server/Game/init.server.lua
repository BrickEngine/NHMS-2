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
local BaseWeapon = require(ReplicatedStorage.Shared.GameSystems.Weapons.Arsenal.BaseWeapon)
local WeaponManager = require(ReplicatedStorage.Shared.GameSystems.Weapons.WeaponManager)
local Network = require(ReplicatedStorage.Shared.Network)
local ServNetApi = require(script.ServNetApi)

local LOOP_DT = 0.05
local DEATH_REMOVE_DELAY = 2.0
local ENABLE_DEATH_EVENT_COOLDOWN = false
local DEATH_EVENT_COOLDOWN = 3.0

local PLAYER_INST_FOLD_NAME = Global.FOLDER_NAMES.PLAYERS
local WALL_INST_FOLD_NAME = Global.FOLDER_NAMES.WALLS
local LAVA_INST_FOLD_NAME = Global.FOLDER_NAMES.LAVA

local VALID_CLIENT_DAMAGE_TYPES = {
    [DamageType.FALL] = true,
    [DamageType.NAPALM] = true,
    [DamageType.EXPLOSION] = true,
    [DamageType.DROWN] = true
}

local deathCooldownList = {} :: {[Player]: number}
local spawnedPlrMap = {} :: {[Player]: boolean?}

------------------------------------------------------------------------------------------------------------------------
-- Initialize Workspace
do
    -- Create Workspace folder for runtime player characters
    if (not Workspace:FindFirstChild(PLAYER_INST_FOLD_NAME)) then
        Instance.new(
            "Folder", Workspace
        ).Name = PLAYER_INST_FOLD_NAME
    end

    -- Check if all collision groups are registered
    for _, groupName in pairs(CollisionGroup) do
        if (not PhysicsService:IsCollisionGroupRegistered(groupName)) then
            warn("Unregistered collision group: " .. groupName)
        end
    end

    -- WallParts folder
    local wallPartsFold = Workspace:FindFirstChild(WALL_INST_FOLD_NAME, true)
    if (wallPartsFold) then
        for _, v: Instance in pairs(wallPartsFold:GetDescendants()) do
            if (v:IsA("BasePart")) then
                v:AddTag(Global.TAG_NAMES.WALL)
            end
        end
    else
        warn("No 'WallParts' folder present; level has no walkable walls")
    end

    -- LavaParts folder
    local lavaPartsFold = Workspace:FindFirstChild(LAVA_INST_FOLD_NAME, true)
    if (lavaPartsFold) then
        for _, v: Instance in pairs(lavaPartsFold:GetDescendants()) do
            if (v:IsA("BasePart")) then
                v:AddTag(Global.TAG_NAMES.LAVA)
            end
        end
    else
        warn("No 'LavaParts' folder present; level has no lava tiles")
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
    spawnedPlrMap[plr] = nil
end

function Game.revivePlayer(plr: Player)
    -- DO NOT REMOVE WEAPONS HERE
    --ServerRoot.resetPlayerData(plr)
    ServerRoot.fullyHealPlayer(plr)
    ServerRoot.resetActiveInvSlot(plr)
    
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
	local spawnPos : Vector3 = (tmpSpawn.CFrame.Position + Vector3.new(0,3,0)) or Vector3.new(0, 50, 0)
    do
        newCharacter.Name = tostring(plr.UserId)
        newCharacter.Parent = Workspace:FindFirstChild(PLAYER_INST_FOLD_NAME)
        newCharacter:MoveTo(spawnPos)

        newCharacter.PrimaryPart:SetNetworkOwner(plr)
        plr.Character = newCharacter
    end

    assert(plr.Character and plr.Character.PrimaryPart, "Playermodel must exist and have a primary part")

    if (Workspace.StreamingEnabled) then
        plr.ReplicationFocus = plr.Character.PrimaryPart
    end

    Game.revivePlayer(plr)

    spawnedPlrMap[plr] = true

	return newCharacter
end

function Game.removeWeaponFromPlayerInventory(plr: Player, uid: number)
    local plrData = ServerRoot.getPlayerData(plr)
    local weap: BaseWeapon.Weapon? = WeaponManager.getWeapFromUid(uid)
    if (not weap) then
        error(`Player '{plr}' has no weapon with uid '{uid}'`)
    end

    ServNetApi.events[Network.serverEvents.removeWeapon]:FireAllClients(weap.uid)

    WeaponManager.destroyWeapon(uid)
    plrData.inventory[weap.slot] = nil
end

function Game.removeAllWeaponsFromPlayerInventory(plr)
    local plrData = ServerRoot.getPlayerData(plr)
    for _, weap: BaseWeapon.Weapon? in pairs(plrData.inventory) do
        if (weap) then
            Game.removeWeaponFromPlayerInventory(plr, weap.uid)
        end
    end
end

-- Adds a new weapon to the player's inventory, or overwrites an occupied inventory slot
function Game.createAndAddWeaponToPlayer(weapOwner: Player, weapName: string, switchToSlot: boolean?)
    local newWeapObj, weapUid = WeaponManager.createWeapon(weapOwner, weapName)
    local weapSlot = newWeapObj.slot
    local plrData = ServerRoot.getPlayerData(weapOwner)
    local switch = switchToSlot or false

    -- if a weapon already exists in this slot, remove iit
    if (plrData.inventory[weapSlot]) then
        warn(`Weapon in slot '{weapSlot}' of '{weapOwner}' was overwritten`)
        Game.removeWeaponFromPlayerInventory(weapOwner, plrData.inventory[weapSlot].uid)
    end
    plrData.inventory[weapSlot] = newWeapObj

    print(`Adding weapon for '{weapOwner}' (owner) with uid '{weapUid}'`)

    -- add local copy for all other players
    ServNetApi.events[Network.serverEvents.addWeapon]:FireAllClients(weapOwner, weapName, weapUid, switch)
end

function Game.equipPlayerStaterGear(plr: Player)
    Game.createAndAddWeaponToPlayer(plr, WeaponName.SWORD, true)
    Game.createAndAddWeaponToPlayer(plr, WeaponName.PLASMA_SPELL)
end

------------------------------------------------------------------------------------------------------------------------
-- Network
------------------------------------------------------------------------------------------------------------------------
-- Event methods

local function onPlayerRequestSpawn(plr: Player)
    if (ENABLE_DEATH_EVENT_COOLDOWN and deathCooldownList[plr] > 0) then
        warn(`{plr} on cooldown`); return
    end
    Game.removeAllWeaponsFromPlayerInventory(plr)
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
    if (newHp > currHp) then 
        warn(`{plr} attempted to heal themselves`); return 
    end
    if (not (damageType and VALID_CLIENT_DAMAGE_TYPES[damageType])) then
        print(VALID_CLIENT_DAMAGE_TYPES[damageType])
        warn("Invalid damage type"); return
    end

    ServerRoot.changePlayerHealth(plr, newHp, damageType)
end

-- Handles any damage requests from players to Entities, including other players
local function onPlayerRequestDamageToEntity(plr: Player, entityMdl: Model?, damage: number?)
    if (typeof(entityMdl) ~= "Instance") then
        warn(`'{plr}' sent invalid entityMdl type for entity damage request`); return
    end
    if (typeof(damage) ~= "number") then
        warn(`'{plr}' sent invalid damage value for entity damage request`); return
    end

    -- TODO: better security and weapon based damage verification

    if (entityMdl and entityMdl:IsA("Model")) then
        local plrFromMdl = Players:GetPlayerFromCharacter(entityMdl)
        if (plrFromMdl) then
            local currVictimData = ServerRoot.getPlayerData(plrFromMdl)
            local newVictimHp = currVictimData.health - damage
            ServerRoot.changePlayerHealth(plrFromMdl, newVictimHp, DamageType.BLADE)
        else
            -- TODO: case for non-player entities
        end
    else
        warn(`No entity from instance '{entityMdl}' found from damage request of '{plr}'`);
        return
    end
end

local function onPlayerRequestActiveWeaponSwitch(weapOwner: Player, newSlot: number?)
    local plrData = ServerRoot.getPlayerData(weapOwner)
    local oldInvSlotWeapon = plrData.inventory[plrData.activeInvSlot]
    local newInvSlotWeapon = nil

    if (newSlot and typeof(newSlot) == "number") then
        if (plrData.activeInvSlot == newSlot) then
            warn(`{weapOwner} already has slot {newSlot} active`); return
        end

        newInvSlotWeapon = plrData.inventory[newSlot]
        if (not newInvSlotWeapon) then
            warn(`{weapOwner} has no weapon in slot {newSlot}`); return
        end

        plrData.activeInvSlot = newSlot
    end

    -- if there is no weapon, return nil for the uid
    local oldInvSlotWeapUID = if oldInvSlotWeapon then oldInvSlotWeapon.uid else nil
    local newInvSlotWeapUID = if newInvSlotWeapon then newInvSlotWeapon.uid else nil

    ServNetApi.events[Network.serverEvents.switchWeapon]:FireAllClients(
        weapOwner, newInvSlotWeapUID, oldInvSlotWeapUID
    )
end

local function onPlayerRequestFireWeapon(plr: Player, pos: Vector3?, dir: Vector3?, params: any?)
    local plrData = ServerRoot.getPlayerData(plr)
    local currWeapon: BaseWeapon.Weapon = plrData.inventory[plrData.activeInvSlot]
    if (not currWeapon) then
        warn(`'{plr}' has no weapon in active inv slot '{plrData.activeInvSlot}'`); return
    end
    if (typeof(pos) ~= "Vector3" or typeof(dir) ~= "Vector3") then
        warn(`'{plr}' sent illegal pos or dir args: pos: '{pos}', dir: '{dir}'`); return
    end
    if (dir.Magnitude == 0) then
        warn(`'{plr}' dir vec has magnitude 0`); return
    end

    local validParams, err = currWeapon:validateFireParams(params)
    if (not validParams) then
        warn(`{plr} sent illegal params: {err}`); return
    end

    ServNetApi.events[Network.serverEvents.fireWeapon]:FireAllClients(currWeapon.uid, pos, dir, params)
end

local function onPlayerSendSimData(plr: Player, payload: buffer?)
    if (not payload or typeof(payload) ~= "buffer") then
        warn(`'{plr}' did not send a payload buffer`); return
    end
    if (buffer.len(payload) > 2) then
        warn(`'{plr}' sent invalid payload`); return
    end
    ServNetApi.fastEvents[Network.serverFastEvents.plrDataToClient]:FireAllClients(plr, payload)
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
    [Network.clientEvents.requestFireWeapon] = function(plr: Player, ...)
        onPlayerRequestFireWeapon(plr, ...)
    end,
    [Network.clientEvents.requestActiveWeaponSwitch] = function(plr: Player, ...)
        onPlayerRequestActiveWeaponSwitch(plr, ...)
    end,
    [Network.clientEvents.requestDamage] = function(plr: Player, ...)
        onPlayerRequestDamageToEntity(plr, ...)
    end,
}

local fastRemEventFunctions = {
    [Network.clientFastEvents.plrDataToServer] = function(plr: Player, ...)
        onPlayerSendSimData(plr, ...)
    end,
}

local remFunctionFunctions = {}

ServNetApi.implementREvents(remEventFunctions)
ServNetApi.implementFastREvents(fastRemEventFunctions)
ServNetApi.implementRFunctions(remFunctionFunctions)

------------------------------------------------------------------------------------------------------------------------
-- Bindable events (signals)

local function onPlayerDied(plr: Player)
    print("player has died")

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

    -- send all existing weapons to player when they spawn

    repeat task.wait(); print("ASDASDASD") until spawnedPlrMap[plr] == true

    for _, otherPlrChar: Model in pairs(Workspace[PLAYER_INST_FOLD_NAME]:GetChildren()) do
        local weapOwner = Players:GetPlayerFromCharacter(otherPlrChar)
        if (plr == weapOwner) then
            continue
        end

        local otherPlrData = ServerRoot.getPlayerData(weapOwner)
        for i: number, weap: BaseWeapon.Weapon in pairs(otherPlrData.inventory) do
            print(`Sending weapon of '{weapOwner}' with uid '{weap.uid}' after '{plr}' joined`)
            ServNetApi.events[Network.serverEvents.addWeapon]:FireClient(
                plr, weapOwner, weap.name, weap.uid, false
            )

            local activeInvSlotWeap = otherPlrData.inventory[otherPlrData.activeInvSlot]
            if (activeInvSlotWeap == weap) then
                ServNetApi.events[Network.serverEvents.switchWeapon]:FireClient(
                    plr, weapOwner, weap.uid, nil
                )
            end
        end
        -- if (otherPlrData.activeInvSlot > 0) then
        --     local activeWeapOfOtherPlr = otherPlrData.inventory[otherPlrData.activeInvSlot] :: BaseWeapon.Weapon
        --     if (activeWeapOfOtherPlr) then
        --         ServNetApi.events[Network.serverEvents.switchWeapon]:FireClient(
        --             plr, weapOwner, activeWeapOfOtherPlr.uid, nil
        --         )
        --     end
        -- end
    end

    -- TODO: also add non owned weapons for each player
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

    -- for _, p: Player in pairs(Players:GetPlayers()) do
    --     local d = ServerRoot.getPlayerData(p)
    --     print(d.inventory)
    -- end
end
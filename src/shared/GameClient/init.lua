--[[
    Main module for all client-side player and game logic.

    lots and lot of TODO here
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
--local CliNetApi = require(script.CliNetApi)
local Network = require(ReplicatedStorage.Shared.Network)
local CliApi = require(script.CliNetApi)
local PlayerData = require(script.Parent.PlayerData)
local CorePlayerUI = require(script.UI.CorePlayerUI)
local PlayerVisuals = require(script.PlayerVisuals)
local CharacterSounds = require(ReplicatedStorage.Shared.CharacterSounds)
local Controller = require(ReplicatedStorage.Shared.Controller)
local Simulation = require(ReplicatedStorage.Shared.Controller.Simulation)
local InputManager = require(ReplicatedStorage.Shared.InputManager)
local SlotSwitchType = require(ReplicatedStorage.Shared.InputManager.SlotSwitchType)

local DamageType = require(ReplicatedStorage.Shared.Enums.DamageType)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local BaseWeapon = require(ReplicatedStorage.Shared.GameSystems.Weapons.Arsenal.BaseWeapon)
local WeaponManager = require(ReplicatedStorage.Shared.GameSystems.Weapons.WeaponManager)

local INVENTORY_SIZE = PlayerData.LIMITS.maxInventorySize

local MIN_FALL_DMG_VEL = 65.0
local MIN_FALL_DMG = 2
local FALL_DMG_COOLDOWN = 0.25
local FALL_DMG_FAC = 1.5

local DEATH_SOUND_MAP = {
    [DamageType.NONE] = CharacterSounds.SOUND_ITEMS.DEATH,
    [DamageType.BLADE] = CharacterSounds.SOUND_ITEMS.DEATH,
    [DamageType.BLUNT] = CharacterSounds.SOUND_ITEMS.DEATH,
    [DamageType.BULLET] = CharacterSounds.SOUND_ITEMS.DEATH,
    [DamageType.EXPLOSION] = CharacterSounds.SOUND_ITEMS.DEATH,
    [DamageType.NAPALM] = CharacterSounds.SOUND_ITEMS.DEATH,
    [DamageType.FALL] = CharacterSounds.SOUND_ITEMS.DEATH_FALL,
    [DamageType.DROWN] = CharacterSounds.SOUND_ITEMS.DEATH_DROWN,
}

local DMG_SOUND_ARR = {
    CharacterSounds.SOUND_ITEMS.DAMAGE_0,
    CharacterSounds.SOUND_ITEMS.DAMAGE_1,
    CharacterSounds.SOUND_ITEMS.DAMAGE_2,
}

local clientEvents = Network.clientEvents
local localPlr = Players.LocalPlayer

local simulation = Controller:getSimulation()
local controllerCamera = Controller:getCamera()
local rootPlrData = ClientRoot.getPlayerData()
local rootSimData = ClientRoot.getSimData()
local rootGameData = ClientRoot.getGameData()

local lastFallVel = 0
local fallCooldown = 0
local switchFree = true -- mutex for controling weapon behavior during active inv slot changes
local targetInvSlot = 0

--local weapIdMap = {} :: {[number]: BaseWeapon.Weapon}

local updateConn: RBXScriptConnection
local charAddedConn: RBXScriptConnection
local charRemovingConn: RBXScriptConnection

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local GameClient = {}

function GameClient.init()
    if (updateConn) then
        (updateConn :: RBXScriptConnection):Disconnect()
    end
    updateConn = RunService.PreRender:Connect(function(dt) 
        GameClient.update(dt) 
    end)

    GameClient.initPlayer()

    return GameClient
end

function GameClient.initPlayer()
    local function onCharAdded(character: Model)
        ClientRoot.setIsDead(false)
        ClientRoot.setHealth(PlayerData.LIMITS.health)
    end

    local function onCharRemoving(character: Model)
        CliApi.events[clientEvents.requestSpawn]:FireServer()
    end

    CliApi.events[clientEvents.requestSpawn]:FireServer()

    if (charAddedConn) then charAddedConn:Disconnect() end
    if (charRemovingConn) then charRemovingConn:Disconnect() end
    charAddedConn = Players.LocalPlayer.CharacterAdded:Connect(onCharAdded)
    charRemovingConn = Players.LocalPlayer.CharacterRemoving:Connect(onCharRemoving)
end

function GameClient.createWeaponLocal(weapName: string, uid: number, ownerMdl: Model?): BaseWeapon.Weapon
    -- local oldWeapon = WeaponManager.getWeapFromUid(uid)
    -- if (oldWeapon) then
    --     error(`Weapon with uid '{uid}' already exists`)
    -- end
    local weapon = WeaponManager.createWeaponForClient(ownerMdl, weapName, uid)
    --weapIdMap[uid] = weapon

    return weapon
end

function GameClient.removeWeaponLocal(uid: number)
    --local weapon = weapIdMap[uid]
    local weapon = WeaponManager.getWeapFromUid(uid)

    if (not weapon) then
        error(`No existing weapon with uid '{uid}'`)
    end

    local plrData = ClientRoot.getPlayerData()

    if (weapon.owner == localPlr.Character) then
        -- in case weapon is currently equipped in active slot
        if (plrData.inventory[plrData.activeInvSlot] == weapon) then
            GameClient.setTargetInvSlot(0)
        end
        ClientRoot.freeInventorySlot(weapon.slot)
    end
    WeaponManager.destroyWeapon(uid)
    -- weapIdMap[uid]:destroy()
    -- weapIdMap[uid] = nil
end

function GameClient.equipWeaponInSlot(slot: number)
    local plrData = ClientRoot.getPlayerData()
    if (plrData.isDead) then
        return
    end

    CliApi.events[Network.clientEvents.requestActiveWeaponSwitch]:FireServer(slot)
    GameClient.setTargetInvSlot(slot)
    ClientRoot.setActiveInvSlot(slot)
    
    GameClient.getActiveWeapon():equip()
end

function GameClient.switchWeapon(newSlot)
    if (not switchFree) then
        warn(`attempted to switch to slot '{newSlot}' while busy`); return
    end

    switchFree = false

    local plrData = ClientRoot.getPlayerData()
    local activeInvSlot = plrData.activeInvSlot

    if (not plrData.inventory[newSlot]) then
        error(`No weapon in slot '{newSlot}' to transition to`)
    end

    if (plrData.inventory[activeInvSlot]) then
        plrData.inventory[activeInvSlot]:unequip()
    end
    GameClient.equipWeaponInSlot(newSlot)

    switchFree = true
end

function GameClient.setTargetInvSlot(newSlot)
    targetInvSlot = newSlot
end

function GameClient.getActiveWeapon()
    local plrData = ClientRoot.getPlayerData()
    return plrData.inventory[plrData.activeInvSlot]
end

-- Changes health and related data locally
function GameClient.changeHealthLocal(newHp: number, damageType: string)
    if (newHp == rootPlrData.health) then
        return
    end
    ClientRoot.setHealth(newHp, damageType)
    --ClientRoot.setIsDead(newHp <= 0)
    if (newHp <= 0) then
        ClientRoot.setIsDead(true)
    end
end

-- Requests health change on the server
function GameClient.changeHealth(newHp: number, damageType: string)
    GameClient.changeHealthLocal(newHp, damageType)
    CliApi.events[clientEvents.requestChangeHealth]:FireServer(newHp, damageType)
end

-- Things to execute when the ClientRoot Event fires
function GameClient.onHealthChanged(newHp: number, hpDiff: number, damageType: string?)
    local _damageType = if (damageType) then damageType else DamageType.NONE
    local ceilOldHP = math.ceil(newHp - hpDiff)
    local ceilNewHP = math.ceil(newHp)

    if (ceilNewHP == ceilOldHP) then
        return
    end

    -- play sounds
    if (hpDiff < 0) then
        if (newHp > 0) then
            local rmdSoundItem = DMG_SOUND_ARR[math.random(1, #DMG_SOUND_ARR)]
            CharacterSounds:updateGlobalSound(rmdSoundItem, true)
        elseif (newHp == 0) then
            local deathSound = DEATH_SOUND_MAP[_damageType]
            CharacterSounds:updateGlobalSound(deathSound, true)
        end
    end
end

function GameClient.onDeathStateChanged(isDead: boolean, lastDamageType: string)
    if (not isDead) then
        -- Revival
        -- TODO: spawn / revive effects
        controllerCamera:activateFPDeathCam(false)
        repeat 
            task.wait()
        until (controllerCamera:getWasFPCamAngleResetAfterDeathCam())

        simulation:toggleReadInput(true)
        -- todo move aimation logic to GameClient and do death anim here
    else
        -- Death
        simulation:toggleReadInput(false)
        controllerCamera:activateFPDeathCam(true)

        local currWeapon: BaseWeapon.Weapon? = GameClient.getActiveWeapon()
        if (currWeapon) then
            currWeapon:unequip()
        end
        ClientRoot.setActiveInvSlot(0)
        targetInvSlot = 0
    end
end

function GameClient.updateFallDamage(dt: number)
    local character = Players.LocalPlayer.Character
    local isDead = rootPlrData.isDead

    if (not character or isDead) then
        return
    end

    local primPart = character.PrimaryPart
    assert(primPart, "No primary part")

    local currFallVel = math.abs(math.min(primPart.AssemblyLinearVelocity.Y, 0))

    local damageConditions = 
        rootSimData.playerStateId == PlayerStateId.GROUND 
        and rootSimData.isGrounded 
        and lastFallVel >= MIN_FALL_DMG_VEL 
        and fallCooldown <= 0

    if (damageConditions) then
        local damage = (lastFallVel - MIN_FALL_DMG_VEL) * FALL_DMG_FAC + MIN_FALL_DMG
        local newHp = rootPlrData.health - damage
        newHp = math.max(0, newHp)
        GameClient.changeHealth(newHp, DamageType.FALL)
        fallCooldown = FALL_DMG_COOLDOWN
    end

    fallCooldown = math.max(0, fallCooldown - dt)
    lastFallVel = currFallVel
end

function GameClient.updateGameTime(dt: number, override: number?)
    local newTime = override or rootGameData.gameTime + dt
    ClientRoot.setGameTime(newTime)
end

function GameClient.updateSimData(dt: number)
    local stateShared = simulation:getStateShared() :: Simulation.SharedVals
    local currStateId = simulation:getCurrentStateId()

    -- ClientRoot.setIsGrounded(stateShared.grounded)
    -- ClientRoot.setIsDashing(stateShared.isDashing)
    ClientRoot.setSimSharedData(
        stateShared.grounded,
        stateShared.inWater,
        stateShared.submerged,
        stateShared.onWaterSurface,
        stateShared.isDashing,
        stateShared.nearWall,
        stateShared.isRightSideWall
    )
    ClientRoot.setCurrentPlayerStateId(currStateId)
end

--[[
    Returns the next occupied slot with a weapon, if it exists
    @param dir - 1 = next, -1 = prev
]]
function GameClient.getNextOccInvSlot(dir: number): number?
    local plrData = ClientRoot.getPlayerData()
    local inventory = plrData.inventory
    local activeInvSlot = plrData.activeInvSlot
    assert(dir == -1 or dir == 1, "Invalid arg for dir")

    local index = activeInvSlot
    for _=1, INVENTORY_SIZE, 1 do
        index += dir
        if (index > INVENTORY_SIZE) then
            index = 1
        elseif (index < 1) then
            index = INVENTORY_SIZE
        end

        if (inventory[index]) then
            return index
        end
    end
    
    return nil
end

function GameClient.updateWeaponInventory(dt: number)
    local plrData = ClientRoot.getPlayerData()
    local switchRequest, switchType, directNum = InputManager:getInvSwitchInput(plrData.activeInvSlot)

    if (plrData.isDead) then
        return
    end

    -- set (overwrite) target inv slot from recent input
    if (switchRequest) then
        local inpTargetSlot
        if (switchType == SlotSwitchType.DIRECT) then
            if (not directNum) then
                error("No direct slot number provided")
            end

            inpTargetSlot = directNum
            if (inpTargetSlot > INVENTORY_SIZE or not plrData.inventory[inpTargetSlot]) then
                inpTargetSlot = nil
            end
        elseif (switchType == SlotSwitchType.NEXT) then
            inpTargetSlot = GameClient.getNextOccInvSlot(1)
        elseif (switchType == SlotSwitchType.PREV) then
            inpTargetSlot = GameClient.getNextOccInvSlot(-1)
        end

        if (inpTargetSlot and inpTargetSlot ~= plrData.activeInvSlot) then
            GameClient.setTargetInvSlot(inpTargetSlot)
        end
    end

    -- switch slots if possible
    if (targetInvSlot ~= plrData.activeInvSlot) then
        local currWeapon: BaseWeapon.Weapon = GameClient.getActiveWeapon()
        local isWeaponActive = currWeapon and currWeapon:getIsFireLocked()

        if (switchFree and not isWeaponActive) then
            GameClient.switchWeapon(targetInvSlot)
        end
    end

    -- update current weapon
    if (switchFree) then
        local currWeapon: BaseWeapon.Weapon = GameClient.getActiveWeapon()
        if (not currWeapon or plrData.isDead) then
            return
        end
        currWeapon:update(dt)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- GameClient update
------------------------------------------------------------------------------------------------------------------------
function GameClient.update(dt: number)
    GameClient.updateGameTime(dt)
    GameClient.updateSimData(dt)
    GameClient.updateFallDamage(dt)
    GameClient.updateWeaponInventory(dt)
end

------------------------------------------------------------------------------------------------------------------------
-- Network

local function onSetHealthRemote(plr: Player, newHp: number, damageType: string?)
    if (plr ~= localPlr) then
        return
    end
    local _damageType = if (damageType) then damageType else DamageType.NONE
    GameClient.changeHealthLocal(newHp, _damageType)
end

local function onAddWeaponToPlayer(plr: Player, weapName: string, uid: number, switchToSlot: boolean)
    -- we trust the server to correctly add weapons, making sure old ones on the same slot are removed first
    local weapon = GameClient.createWeaponLocal(weapName, uid, plr.Character) :: BaseWeapon.Weapon
    print(`adding local weapon to player with uid '{uid}'`)

    if (not plr.Character) then
        plr.CharacterAdded:Wait()
    end
    weapon:setOwner(plr.Character)

    if (plr == localPlr) then
        local plrData = ClientRoot.getPlayerData()
        plrData.inventory[weapon.slot] = weapon
        ClientRoot.occupyInventorySlot(weapon.slot, weapon)

        --GameClient.setTargetInvSlot(weapon.slot)
        if (switchToSlot) then
            --GameClient.switchWeaponSlot(weapon.slot)
            GameClient.setTargetInvSlot(weapon.slot)
        end
    end
end

local function onRemoveWeaponFromPlayer(plr: Player, uid: number)
    GameClient.removeWeaponLocal(uid)
end

local function onFireWeapon(uid: number, altFire: boolean)
    local weapon = WeaponManager.getWeapFromUid(uid)
    if (weapon.owner == localPlr.Character) then
        return
    end
    weapon:fire(altFire)
end

local cliREFunction = {
    [Network.serverEvents.playSound] = function(plr: Player, item: string, play: boolean)
        CharacterSounds:updatePlayerSound(plr, item, play)
    end,
    [Network.serverEvents.setHealth] = function(plr: Player, hp: number, damageType: string)
        onSetHealthRemote(plr, hp, damageType)
    end,
    [Network.serverEvents.addWeaponToPlayer] = function(
        plr: Player, weaponName: string, uid: number, switchToSlot: boolean)
        onAddWeaponToPlayer(plr, weaponName, uid, switchToSlot)
    end,
    [Network.serverEvents.removeWeaponFromPlayer] = function(plr: Player, uid: number)
        onRemoveWeaponFromPlayer(plr, uid)
    end,
    [Network.serverEvents.fireWeapon] = function(uid: number, altFire: boolean)
        onFireWeapon(uid, altFire)
    end,
}

local cliFastREFunctions = {
    [Network.serverFastEvents.jointsDataToClient] = function(plr: Player, ...)
        -- TODO
    end,
}

CliApi.implementREvents(cliREFunction)
CliApi.implementFastREvents(cliFastREFunctions)

------------------------------------------------------------------------------------------------------------------------
-- Local events
ClientRoot.signals.deathStateChanged.Event:Connect(GameClient.onDeathStateChanged)
ClientRoot.signals.healthChanged.Event:Connect(GameClient.onHealthChanged)

------------------------------------------------------------------------------------------------------------------------

GameClient.init()
PlayerVisuals.init()
CorePlayerUI.disableAll()
CorePlayerUI.setActive(CorePlayerUI.UIType.GAME)

return GameClient
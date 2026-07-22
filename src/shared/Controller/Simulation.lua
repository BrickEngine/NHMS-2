local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)
local FuncUtil = require(ReplicatedStorage.Shared.Util.FuncUtil)
local DebugVisualize = require(script.Parent.Common.DebugVisualize)

local InputManager = require(ReplicatedStorage.Shared.InputManager)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local CliNetApi = require(ReplicatedStorage.Shared.GameClient.CliNetApi)
local Network = require(ReplicatedStorage.Shared.Network)
local simStates = script.Parent.SimStates
local BaseState = require(simStates.BaseState)
local Universal = require(simStates.Universal) :: BaseState.BaseState
local Ground = require(simStates.Ground) :: BaseState.BaseState
local Water = require(simStates.Water) :: BaseState.BaseState
local Wall = require(simStates.Wall) :: BaseState.BaseState

local PRINT_DEBUG = false

local PAYLOAD_DELAY = 0.05 -- ~20Hz

local STATE_SHARED_VALS = table.freeze({
    grounded = false,
    inWater = false,
    submerged = false,
    onWaterSurface = false,
    isDashing = false,
    nearWall = false,
    isRightSideWall = false,
    stateTime = 0
})

local VEC3_UP = Vector3.new(0, 1, 0)

-- local vars
local state_free = true
local dataTime = 0

local updateConn: RBXScriptConnection?
local simUpdateConn: RBXScriptConnection?
local primaryPartListener: RBXScriptConnection?

local stateSharedDefaults = FuncUtil.deepCopy(STATE_SHARED_VALS)

local function createBuoySensor(mdl: Model): BuoyancySensor
    assert(mdl.PrimaryPart)

    local buoyAtt = Instance.new("Attachment", mdl.PrimaryPart)
    buoyAtt.WorldAxis = VEC3_UP
    buoyAtt.Name = "Buoy"

    local buoySens = Instance.new("BuoyancySensor", mdl.PrimaryPart)
    buoySens.UpdateType = Enum.SensorUpdateType.OnRead

    return buoySens
end

local function disconnectAllUpdateConns()
    if (updateConn) then
        updateConn:Disconnect()
    end
    if (simUpdateConn) then
        simUpdateConn:Disconnect()
    end
end

------------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------------
local Simulation = {}
Simulation.__index = Simulation

-- types
export type Simulation = typeof(Simulation)
export type SharedVals = typeof(STATE_SHARED_VALS)

function Simulation.init()
    local self = setmetatable({}, Simulation) :: any
    self.states = {}
    self.currentState = nil
    self.universalState = nil

    self.allowTransitions = true
    self.stateShared = stateSharedDefaults
    self.isDead = true
    self.camAngleReset = false
    self.buoySensor = nil

    self.character = Players.LocalPlayer.Character

    Players.LocalPlayer.CharacterAdded:Connect(function(char) self:onCharAdded(char) end)
    Players.LocalPlayer.CharacterRemoving:Connect(function(char) self:onCharRemoving(char) end)

    if Players.LocalPlayer.Character then
		self:onCharAdded(Players.LocalPlayer.Character)
	end

    return self
end

function Simulation:onCharAdded(character: Model)
    self.character = character

    if (primaryPartListener) then
        primaryPartListener:Disconnect()
    end
    if (not self.character.PrimaryPart) then
        error("character missing PrimaryPart")
    end
    --self.character.PrimaryPart.Removing
    primaryPartListener = self.character.DescendantRemoving:Connect(function()
        self:onRootPartChanged()
    end)

    -- make playermodel invisible
    for _, p: Instance in pairs(self.character:GetDescendants()) do
        if p:IsA("BasePart") then
            if (p.CollisionGroup ~= CollisionGroup.PLAYER) then
                continue
            end
            p.Transparency = 1
        end
    end

    -- copy over Instances from StarterCharacterScripts
    -- TODO: move logic over to GameClient
    for _, s: Instance in pairs(StarterPlayer.StarterCharacterScripts:GetChildren()) do
        if (s.ClassName ~= ("LocalScript" or "Script" or "ModuleScript")) then
            warn("instance within StarterCharacterScripts is not a script")
        end
        local sClone = s:Clone()
        sClone.Parent = self.character
    end

    self:resetSimulation()

    --TEST_DESPAWNING()
end

function Simulation:onCharRemoving(character: Model)
    disconnectAllUpdateConns()

    if (Players.LocalPlayer.Character) then
        Players.LocalPlayer.Character:Destroy()
        Players.LocalPlayer.Character = nil
    end
end

function Simulation:transitionState(newStateId: number, params: any?)
    state_free = false

    if (PRINT_DEBUG) then
        print(`Transitioning from {self.currentState.id} to {newStateId}`)
    end

    local oldStateId = self.currentState.id
    local newState = self.states[newStateId]
    assert(newState, "Cannot transition to nonexistent state")

    self.currentState:stateLeave()
    self.currentState = newState
    self.currentState:stateEnter(oldStateId, params)

    self.stateShared.stateTime = 0

    state_free = true
end

function Simulation:getCurrentStateId(): number
    if (self.currentState) then
        return self.currentState.id
    end
    return PlayerStateId.NONE
end

function Simulation:getStateShared(): SharedVals
    return self.stateShared
end

function Simulation:getCurrentSimData(): ClientRoot.SimData
    local stateId = (self.currentState and self.currentState.id) or PlayerStateId.NONE
    return {
        playerStateId = stateId,
        isGrounded = self.stateShared.grounded,
        inWater = self.stateShared.inWater,
        submerged = self.stateShared.submerged,
        onWaterSurface = self.stateShared.onWaterSurface,
        isDashing = self.stateShared.isDashing,
        nearWall = self.stateShared.nearWall,
        isRightSideWall = self.stateShared.isRightSideWall
    }
end


function Simulation:resetStateShared()
    self.stateShared = stateSharedDefaults
end

function Simulation:toggleReadInput(readInput: boolean)
    self.isDead = not readInput
    if (self.isDead) then
        self.camAngleReset = false
    end
    InputManager:setControlsEnabled(readInput)
end

-- Stuns the player by forcing state transitions or other effects, depending on the current state
function Simulation:stun()
    if (not self.currentState) then
        warn("No active state"); return
    end
    self.currentState:stun()
end

function Simulation:onRootPartChanged()
    if (not self.character.PrimaryPart) then
        warn("PrimaryPart of character removed -> halting simulation, removing character")
        self:onCharRemoving(Players.LocalPlayer.Character)
    end
end

function Simulation:resetSimulation()
    assert(self.character, "character missing")
    assert(self.character.PrimaryPart, "primary part missing")

    disconnectAllUpdateConns()
    self:resetStateShared()

    if (self.buoySensor) then
        (self.buoySensor :: BuoyancySensor):Destroy()
    end
    self.buoySensor = createBuoySensor(self.character)

    if (self.states :: {[number]: BaseState.BaseState}) then
        for id: number, _ in pairs(self.states) do
            self.states[id]:destroy()
            self.states[id] = nil
        end
    end
    if (self.universalState) then
        self.universalState:destroy()
        self.universalState = nil
    end

    self.universalState = Universal.new(self)
    self.universalState:stateEnter()

    self.states = {
        [PlayerStateId.GROUND] = Ground.new(self),
        [PlayerStateId.WATER] = Water.new(self),
        [PlayerStateId.WALL] = Wall.new(self)
    }
    self.currentState = self.states[PlayerStateId.GROUND]
    self.currentState:stateEnter(PlayerStateId.NONE)
    self.stateTime = 0

    -- BindToSimulation causes descrepancies with physics atm 
    -- (StepFreq of 120Hz and 240Hz should be added as an option)

    -- simUpdateConn = RunService:BindToSimulation(
    --     function(dt) self:simUpdate(dt) end, 
    --     Enum.StepFrequency.Hz60
    -- )
    simUpdateConn = RunService.PreSimulation:Connect(
        function(dt: number) self:simUpdate(dt) end
    )

    updateConn = RunService.PostSimulation:Connect(
        function(dt: number) self:update(dt) end
    )
    dataTime = 0

    InputManager:setControlsEnabled(true)
end

function Simulation:serializeSimData(): buffer
    if (not self.stateShared) then error("stateShared vals not initialized") end

    local shared: SharedVals = self.stateShared
    local offset = 0
    local flags = 0
    if (shared.grounded)        then flags = bit32.bor(flags, bit32.lshift(1, 0)) end
    if (shared.inWater)         then flags = bit32.bor(flags, bit32.lshift(1, 1)) end
    if (shared.submerged)          then flags = bit32.bor(flags, bit32.lshift(1, 2)) end
    if (shared.onWaterSurface)  then flags = bit32.bor(flags, bit32.lshift(1, 3)) end
    if (shared.isDashing)       then flags = bit32.bor(flags, bit32.lshift(1, 4)) end
    if (shared.nearWall)        then flags = bit32.bor(flags, bit32.lshift(1, 5)) end
    if (shared.isRightSideWall) then flags = bit32.bor(flags, bit32.lshift(1, 6)) end

    local buf = buffer.create(2)
    buffer.writeu8(buf, offset, flags); offset += 1
    buffer.writei8(buf, offset, self.currentState.id)

    return buf
end

function Simulation:deserializeSimData(payload: buffer): ClientRoot.SimData
    local offset = 0
    local flags = buffer.readu8(payload, offset); offset += 1
    local stateId = buffer.readi8(payload, offset)

    local simData = {
        playerStateId   = stateId,
        isGrounded      = bit32.band(flags, bit32.lshift(1, 0)) ~= 0,
        inWater         = bit32.band(flags, bit32.lshift(1, 1)) ~= 0,
        submerged       = bit32.band(flags, bit32.lshift(1, 2)) ~= 0,
        onWaterSurface  = bit32.band(flags, bit32.lshift(1, 3)) ~= 0,
        isDashing       = bit32.band(flags, bit32.lshift(1, 4)) ~= 0,
        nearWall        = bit32.band(flags, bit32.lshift(1, 5)) ~= 0,
        isRightSideWall = bit32.band(flags, bit32.lshift(1, 6)) ~= 0
    }

    return simData
end

-- TESTING PURPOSES
-- local function TEST_DESPAWNING()
--     print("TESTING RANDOM CHARACTER BREAKING")
--     task.spawn(function()
--         local pTbl = {}
--         local char = Players.LocalPlayer.Character
--         for i,v in pairs(char:GetChildren()) do
--             if (v:IsA("BasePart")) then
--                 table.insert(pTbl, v)
--             end
--         end
--         while (#pTbl > 0) do
--             task.wait(0.001)
--             local rdm = math.random(1, #pTbl)
--             pTbl[rdm]:Destroy()
--             table.remove(pTbl, rdm)
--         end
--         --Players.LocalPlayer.Character:Destroy()
--     end)
-- end

------------------------------------------------------------------------------------------------------------------------------
-- Simulation update
------------------------------------------------------------------------------------------------------------------------------

-- Should be bound to RunService.PostSimulation
function Simulation:simUpdate(dt: number)
    if (not self.character.PrimaryPart) then
        warn("Missing PrimaryPart of character, disconnecting simulation update func");
        disconnectAllUpdateConns(); return
    end

    -- Skip the update cycle, if state transition not complete
    if (not state_free) then
        return
    end

    self.universalState:update(dt)
    self.currentState:update(dt)

    self.stateShared.stateTime += dt

    DebugVisualize.step()
end

function Simulation:update(dt: number)
    if (dataTime <= 0) then
        dataTime = PAYLOAD_DELAY
        local payload = self:serializeSimData() :: buffer
        CliNetApi.fastEvents[Network.clientFastEvents.plrDataToServer]:FireServer(payload)
    end

    dataTime -= dt
end

return Simulation.init()
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--local CharacterDef = require(ReplicatedStorage.Shared.CharacterDef)
local Animation = require(script.Parent.Animation)
local DebugVisualize = require(script.Parent.Common.DebugVisualize)

local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local simStates = script.Parent.SimStates
local BaseState = require(simStates.BaseState)
local Universal = require(simStates.Universal) :: BaseState.BaseState
local Ground = require(simStates.Ground) :: BaseState.BaseState
local Water = require(simStates.Water) :: BaseState.BaseState
local Wall = require(simStates.Wall) :: BaseState.BaseState

local PRINT_DEBUG = true

local STATE_SHARED_VALS = table.freeze({
    grounded = false,
    inWater = false,
    underWater = false,
    onWaterSurface = false,
    isDashing = false,
    nearWall = false,
    isRightSideWall = false,
    stateTime = 0
})

local VEC3_UP = Vector3.new(0, 1, 0)

-- Local vars
local primaryPartListener: RBXScriptConnection
local state_free = true

local function createBuoySensor(mdl: Model): BuoyancySensor
    assert(mdl.PrimaryPart)

    local buoyAtt = Instance.new("Attachment", mdl.PrimaryPart)
    buoyAtt.WorldAxis = VEC3_UP
    buoyAtt.Name = "Buoy"

    local buoySens = Instance.new("BuoyancySensor", mdl.PrimaryPart)
    buoySens.UpdateType = Enum.SensorUpdateType.OnRead

    return buoySens
end

local function deepCopy(tbl: {}): {}
    local copy = {}
    for k, v in pairs(tbl) do
        if (type(v) == "table") then
            -- Recursively copy nested tables
            copy[k] = deepCopy(v)
        else
            -- Copy non-table values directly
            copy[k] = v
        end
    end
    return copy
end

------------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------------
local Simulation = {}
Simulation.__index = Simulation

-- types
export type Simulation = typeof(Simulation)
export type SharedVals = typeof(STATE_SHARED_VALS)

function Simulation.new()
    local self = setmetatable({}, Simulation) :: any
    self.states = {}
    self.currentState = nil
    self.universalState = nil
    self.simUpdateConn = nil
    self.animation = nil

    self.stateShared = nil
    self.buoySensor = nil

    self.character = Players.LocalPlayer.Character

    Players.LocalPlayer.CharacterAdded:Connect(function(char) self:onCharAdded(char) end)
    Players.LocalPlayer.CharacterRemoving:Connect(function(char) self:onCharRemoving(char) end)

    if Players.LocalPlayer.Character then
		self:onCharAdded(Players.LocalPlayer.Character)
	end

    return self
end

------------------------------------------------------------------------------------------------------------------------------
-- Simulation update
------------------------------------------------------------------------------------------------------------------------------

-- Should be bound to RunService.PostSimulation
function Simulation:update(dt: number)
    if (not self.character.PrimaryPart) then
        warn("Missing PrimaryPart of character, disconnecting simulation update func")
        self.simUpdateConn:Disconnect(); return
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

function Simulation:getNormal(): Vector3
    if (self.currentState and self.currentState.normal) then
        return self.currentState.normal
    end
    return Vector3.zero
end

function Simulation:getIsDashing(): boolean
    if (self.currentState) then
        return self.currentState.isDashing
    end
    return false
end

function Simulation:getNearWall(): (boolean, boolean)
    if (self.currentState) then
        return self.stateShared.nearWall, self.stateShared.isRightSideWall
    end
    return false, false
end

function Simulation:onRootPartChanged()
    if (not self.character.PrimaryPart) then
        warn("PrimaryPart of character removed -> halting simulation, removing character")
        self:onCharRemoving(Players.LocalPlayer.Character)
    end
end

function Simulation:resetStateShared()
    self.stateShared = deepCopy(STATE_SHARED_VALS)
end

function Simulation:resetSimulation()
    assert(self.character, "character missing")
    assert(self.character.PrimaryPart, "primary part missing")

    if (self.simUpdateConn :: RBXScriptConnection) then
        self.simUpdateConn:Disconnect()
    end
    if (self.animation) then
        self.animation:destroy()
    end

    self.animation = Animation.new(self)

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

    self.simUpdateConn = RunService.PostSimulation:Connect(function(dt)
        self:update(dt)
    end)
end

function Simulation:serialize(sharedVals: SharedVals): buffer
    if (not self.stateShared) then error("stateShared vals not initialized") end

    local shared: SharedVals = self.stateShared
    local offset = 0
    local flags = 0
    if (shared.grounded)        then flags = bit32.bor(flags, bit32.lshift(1, 0)) end
    if (shared.inWater)         then flags = bit32.bor(flags, bit32.lshift(1, 1)) end
    if (shared.underWater)      then flags = bit32.bor(flags, bit32.lshift(1, 2)) end
    if (shared.onWaterSurface)  then flags = bit32.bor(flags, bit32.lshift(1, 3)) end
    if (shared.isDashing)       then flags = bit32.bor(flags, bit32.lshift(1, 4)) end
    if (shared.nearWall)        then flags = bit32.bor(flags, bit32.lshift(1, 5)) end
    if (shared.isRightSideWall) then flags = bit32.bor(flags, bit32.lshift(1, 6)) end

    local buf = buffer.create(1)
    buffer.writeu8(buf, offset, flags); offset += 1
    buffer.writei8(buf, offset, self.currentState)

    return buf
end

function Simulation:deserialize()
    --TODO
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

    -- Make playermodel invisible
    for _, p: Instance in pairs(self.character:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Transparency = 1
        end
    end

    -- Copy over Instances from StarterCharacterScripts
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
    self.simUpdateConn:Disconnect()

    if (Players.LocalPlayer.Character) then
        Players.LocalPlayer.Character:Destroy()
        Players.LocalPlayer.Character = nil
    end
end

return Simulation.new()
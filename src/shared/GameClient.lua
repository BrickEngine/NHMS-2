--[[
    Main module for all client-side player and game logic.

    lots and lot of TODO here
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local InputManager = require(ReplicatedStorage.Shared.Controller.InputManager)
local Network = require(ReplicatedStorage.Shared.Network)
local CliApi = require(ReplicatedStorage.Shared.Network.CliNetApi)

-- Init Controller singleton
require(ReplicatedStorage.Shared.Controller)

local clientEvents = Network.clientEvents

local DASH_TIME = 1.6 --seconds
local DASH_COOLDOWN_TIME = 0.8 --seconds
local DEFAULT_HEALTH = 100

type Counter = {
    t: number,
    cooldown: number
}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local updateConn = nil

local GameClient = {
    gameTime = 0,
}
GameClient.__index = GameClient

function GameClient.init()
    
end

function GameClient:InitPlayer()
    local function respawnAfterCharRemove(character: Model)
        print(character.Name .. " was removed")
        --task.wait(1.5)
        CliApi[clientEvents.requestSpawn]()
    end

    CliApi[clientEvents.requestSpawn]()
    Players.LocalPlayer.CharacterRemoving:Connect(respawnAfterCharRemove)
end

function GameClient:updateGameTime(dt: number, override: number?)
    if (override) then self.gameTime = override end
    self.gameTime += dt
end

local lastDashInput = false
function GameClient:updateDash(dt: number)
    local input = InputManager:getDashKeyDown()
    local dashImpulse = false

    if (self.dash.cooldown <= 0) then
        dashImpulse = input and not lastDashInput

        if (self.isDashing and (not input or self.dash.t <= 0)) then
            self.dash.t = 0
            self.dash.cooldown = DASH_COOLDOWN_TIME
            self.isDashing = false
        end
    end

    if (dashImpulse) then
        self.dash.t = DASH_TIME
        self.isDashing = true
    end

    self.dash.cooldown = math.max(self.dash.cooldown - dt, 0)
    if (self.isDashing) then
        self.dash.t = math.max(self.dash.t - dt, 0)
    end

    lastDashInput = input
end

------------------------------------------------------------------------------------------------------------------------
-- GameClient update
------------------------------------------------------------------------------------------------------------------------
function GameClient:update(dt: number)
    self:updateGameTime(dt)
end

-- Sets player data default values and stops execution
function GameClient:reset()
    self.gameTime = 0
    self.currentInvSlot = 0
    self.health = DEFAULT_HEALTH
    self.armor = 0

    self.dash = {t = DASH_TIME, cooldown = 0} :: Counter
    self.isDashing = false

    if (updateConn) then
        (updateConn :: RBXScriptConnection):Disconnect()
    end
    updateConn = RunService.PreSimulation:Connect(
        function(dt) self:update(dt) end
    )
end

return GameClient
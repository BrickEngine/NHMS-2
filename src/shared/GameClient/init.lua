--[[
    Main module for all client-side player and game logic

    lots and lot of TODO here
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InputManager = require(ReplicatedStorage.Shared.Controller.InputManager)

local DASH_TIME = 1.6 --seconds
local DASH_COOLDOWN_TIME = 0.8 --seconds
local DEFAULT_HEALTH = 100

local updateConn = nil

type Counter = {
    t: number,
    coolDown: number
}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local GameClient = {
    gameTime = 0,
    currentInvSlot = 0,
    health = 0,
    armor = 0,

    dash = {t = 0, coolDown = 0} :: Counter,
    isDashing = false,

    kills = 0,
    score = 0,
}
GameClient.__index = GameClient

function GameClient:updateGameTime(dt: number, override: number?)
    if (override) then self.gameTime = override end
    self.gameTime += dt
end

function GameClient:getIsDashing()
    return self.isDashing
end

local lastDashInput = false
local dashImpulse = false
function GameClient:updateDash(dt: number)
    local input = InputManager:getDashKeyDown()

    if (self.dash.coolDown <= 0) then
        dashImpulse = (input and not lastDashInput) and true or false

        if (self.isDashing and not input) then
            self.dash.t = 0
            self.dash.coolDown = DASH_COOLDOWN_TIME
            self.isDashing = false
        end
    end

    if (dashImpulse) then
        self.dash.t = DASH_TIME
        self.isDashing = true
    end
    if (self.dash.t <= 0) then
        self.isDashing = false
    end

    self.dash.coolDown = math.max(self.dash.coolDown - dt, 0)
    if (self.isDashing) then
        self.dash.t = math.max(self.dash.t - dt, 0)
    end

    print(self.dash.coolDown, self.dash.t)

    lastDashInput = input
    dashImpulse = false
end

------------------------------------------------------------------------------------------------------------------------
-- GameClient update
------------------------------------------------------------------------------------------------------------------------
function GameClient:update(dt: number)
    self:updateGameTime(dt)
    self:updateDash(dt)
end

-- Sets player data default values and stops execution
function GameClient:reset()
    self.gameTime = 0
    self.currentInvSlot = 0
    self.health = DEFAULT_HEALTH
    self.armor = 0

    self.dash = {t = DASH_TIME, coolDown = 0} :: Counter
    self.isDashing = false

    if (updateConn) then
        (updateConn :: RBXScriptConnection):Disconnect()
    end
    updateConn = RunService.PreSimulation:Connect(
        function(dt) self:update(dt) end
    )
end

return GameClient
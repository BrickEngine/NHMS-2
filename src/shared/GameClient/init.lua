--[[
    Main module for all client-side player and game logic

    lots and lot of TODO here
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local InputManager = require(ReplicatedStorage.Shared.Controller.InputManager)

local DASH_TIME = 4 --seconds
local DASH_COOLDOWN_TIME = 1 --seconds
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
    -- resetable
    gameTime = 0,
    dash = {t = 0, coolDown = 0} :: Counter,
    currentInvSlot = 0,
    health = 0,
    armor = 0,

    -- not resetable
    kills = 0,
    score = 0,
}
GameClient.__index = GameClient

function GameClient:updateGameTime(dt: number, override: number?)
    if (override) then self.gameTime = override end
    self.gameTime += dt
end

function GameClient:updateDash(dt: number)
    if (self.dash.t > 0) then
        if (InputManager:getIsDashing()) then
            self.dash = {
                t = math.max(self.dash.t - dt, 0),
                coolDown = DASH_COOLDOWN_TIME
            }
        end
    else
        self.dash.coolDown = math.max(self.dash.coolDown - dt, 0)
    end

    if (self.dash.coolDown <= 0) then
        self.dash.t = math.min(self.dash.t + dt, DASH_TIME)
    end
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
    self.dash = {t = DASH_TIME, coolDown = 0} :: Counter
    self.currentInvSlot = 0
    self.health = DEFAULT_HEALTH
    self.armor = 0

    if (updateConn) then
        (updateConn :: RBXScriptConnection):Disconnect()
    end
    updateConn = RunService.PreSimulation:Connect(
        function(dt) self:update(dt) end
    )
end

return GameClient
--[[
    Main module for all client-side player and game logic.

    lots and lot of TODO here
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

--local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local Network = require(ReplicatedStorage.Shared.Network)
local CliApi = require(script.CliNetApi)
local SoundManager = require(ReplicatedStorage.Shared.SoundManager)

-- Init Controller singleton
require(ReplicatedStorage.Shared.Controller)

local clientEvents = Network.clientEvents

local DEFAULT_HEALTH = 100

local updateConn: RBXScriptConnection
local charConn: RBXScriptConnection

------------------------------------------------------------------------------------------------------------------------
-- Network
------------------------------------------------------------------------------------------------------------------------

local cliREFunction = {
    [Network.serverEvents.playSound] = function(plr: Player, item: string, play: boolean)
        SoundManager:updatePlayerSound(plr, item, play)
    end
}

local cliFastREFunctions = {
    [Network.serverFastEvents.jointsDataToClient] = function(plr: Player, ...)
        -- TODO
    end,
}

CliApi.implementREvents(cliREFunction)
CliApi.implementFastREvents(cliFastREFunctions)

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local GameClient = {
    gameTime = 0,
}

function GameClient.init()
    GameClient:initPlayer()
end

function GameClient:initPlayer()
    local function respawnAfterCharRemove(character: Model)
        print(character.Name .. " was removed")
        --task.wait(1.5)
        CliApi.events[clientEvents.requestSpawn]:FireServer()
    end

    CliApi.events[clientEvents.requestSpawn]:FireServer()

    if (charConn) then
        charConn:Disconnect()
    end
    charConn = Players.LocalPlayer.CharacterRemoving:Connect(respawnAfterCharRemove)
end

function GameClient:updateGameTime(dt: number, override: number?)
    if (override) then self.gameTime = override end
    print(self.gameTime)
    self.gameTime += dt
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

    if (updateConn) then
        (updateConn :: RBXScriptConnection):Disconnect()
    end
    updateConn = RunService.PreSimulation:Connect(
        function(dt) self:update(dt) end
    )
end

GameClient.init()

return GameClient
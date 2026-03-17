--[[
    Main module for all client-side player and game logic.

    lots and lot of TODO here
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local Network = require(ReplicatedStorage.Shared.Network)
local CliApi = require(script.CliNetApi)
local SoundManager = require(ReplicatedStorage.Shared.SoundManager)
local CorePlayerUI = require(script.UI.CorePlayerUI)
local UIType = require(ReplicatedStorage.Shared.Enums.UIType)

-- Init Controller singleton
require(ReplicatedStorage.Shared.Controller)

local clientEvents = Network.clientEvents
local localPlr = Players.LocalPlayer

local updateConn: RBXScriptConnection
local charConn: RBXScriptConnection

local localData = ClientRoot.getPlrData()

------------------------------------------------------------------------------------------------------------------------
-- Network

local function onSetHealth(plr: Player, val: number)
    if (plr ~= localPlr) then
        return
    end
    ClientRoot.setHealth(val)
    ClientRoot.setIsDead(localData.health <= 0)
end

local cliREFunction = {
    [Network.serverEvents.playSound] = function(plr: Player, item: string, play: boolean)
        SoundManager:updatePlayerSound(plr, item, play)
    end,
    [Network.serverEvents.setHealth] = function(plr: Player, val: number)
        onSetHealth(plr, val)
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

local GameClient = {}

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
    local newTime = override or ClientRoot.getGameTime() + dt
    ClientRoot.setGameTime(newTime)
end

------------------------------------------------------------------------------------------------------------------------
-- GameClient update
------------------------------------------------------------------------------------------------------------------------
function GameClient:update(dt: number)
    self:updateGameTime(dt)
end

-- Sets player data default values and stops execution
function GameClient:reset()
    if (updateConn) then
        (updateConn :: RBXScriptConnection):Disconnect()
    end
    updateConn = RunService.PreSimulation:Connect(
        function(dt) self:update(dt) end
    )
end

GameClient.init()

CorePlayerUI.init()
CorePlayerUI.setActive(UIType.GAME)

return GameClient
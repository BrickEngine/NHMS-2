local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Init character controller
require(ReplicatedStorage.Shared.Controller)

local Network = require(ReplicatedStorage.Shared.Network)
local CliApi = require(ReplicatedStorage.Shared.Network.CliNetApi)
local GameClient = require(ReplicatedStorage.Shared.GameClient)

GameClient:reset()

local clientEvents = Network.clientEvents

-- TODO:
-- request streaming position with RequestStreamAroundAsync(), which is returned from
-- the CliApi[clientEvents.requestSpawn]() RemoteFunction instead of RemoteEvent

-- while (not Players.LocalPlayer.ReplicationFocus) do
--     print("waiting")
--     task.wait()
-- end

local function respawnAfterCharRemove(character: Model)
    print(character.Name .. " was removed")
    --task.wait(1.5)
    CliApi[clientEvents.requestSpawn]()
end

print("client requests character for first time")
CliApi[clientEvents.requestSpawn]()

Players.LocalPlayer.CharacterRemoving:Connect(respawnAfterCharRemove)
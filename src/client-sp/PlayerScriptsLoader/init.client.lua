local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage.Shared.GameClient)

-- TODO:
-- request streaming position with RequestStreamAroundAsync(), which is returned from
-- the CliApi[clientEvents.requestSpawn]() RemoteFunction instead of RemoteEvent

-- while (not Players.LocalPlayer.ReplicationFocus) do
--     print("waiting")
--     task.wait()
-- end

-- local function respawnAfterCharRemove(character: Model)
--     print(character.Name .. " was removed")
--     --task.wait(1.5)
--     CliApi[clientEvents.requestSpawn]()
-- end

-- print("client requests character for first time")
-- CliApi[clientEvents.requestSpawn]()

-- Players.LocalPlayer.CharacterRemoving:Connect(respawnAfterCharRemove)
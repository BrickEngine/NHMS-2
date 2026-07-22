--[[
    Helper module for managing sim data of every active player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local FuncUtil = require(ReplicatedStorage.Shared.Util.FuncUtil)

export type Data = {
    playerStateId: number,
    isGrounded: boolean,
    inWater: boolean,
    submerged: boolean,
    onWaterSurface: boolean,
    isDashing: boolean,
    nearWall: boolean,
    isRightSideWall: boolean,
}

local data = {} :: {[Player]: Data?}

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local SimData = {
    DEFAULT = table.freeze({
        playerStateId = PlayerStateId.NONE,
        isGrounded = false,
        inWater = false,
        submerged = false,
        onWaterSurface = false,
        isDashing = false,
        nearWall = false,
        isRightSideWall = false,
    }) :: Data
}

function SimData.init()
    local function onPlayerAdded(plr: Player)
        SimData.createPlayerData(plr)
    end

    local function onPlayerRemoving(plr: Player)
        SimData.removePlayerData(plr)
    end

    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)

    for _, plr: Player in pairs(Players:GetPlayers()) do
        onPlayerAdded(plr)
    end
    return SimData
end

function SimData.getData(plr: Player): Data
    return data[plr]
end

function SimData.writeData(plr: Player, newSimData: Data)
    local currPlrData = data[plr]
    for i: string, v in pairs(newSimData) do
        currPlrData[i] = v
    end
end

function SimData.createPlayerData(plr: Player)
    if (data[plr]) then
        warn(`'{plr}' already has a sim data entry`)
    end
    data[plr] = FuncUtil.deepCopy(SimData.DEFAULT)
end

function SimData.removePlayerData(plr: Player)
    if (not data[plr]) then
        warn(`'{plr}' has no sim data`); return
    end
    data[plr] = nil
end

return SimData.init()
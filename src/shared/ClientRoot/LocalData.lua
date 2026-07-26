-- Helper module for local client data

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FuncUtil = require(ReplicatedStorage.Shared.Util.FuncUtil)

local data = {} :: any

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local LocalData = {}

export type Data = {
    oxygen: number
}

LocalData.DEFAULTS = table.freeze({
    oxygen = 100
})

LocalData.LIMITS = table.freeze({
    minOxygen = 0,
    maxOxygen = 100
})

LocalData.DEFAULT_DATA = table.freeze({
    oxygen = LocalData.DEFAULTS.oxygen
}) :: Data

function LocalData.removeData()
    if (not data) then
        warn("No local data to clear"); return
    end

    data = nil
end

function LocalData.createData(): Data
    if (data) then
        warn("Existing local data was overwritten")
        LocalData.removeData()
    end

    local newData = FuncUtil.deepCopy(LocalData.DEFAULT_DATA) :: Data
    data = newData

    return data
end

function LocalData.fullyResetData()
    if (not data) then
        error("No local data to reset")
    end
    LocalData.removeData()
    LocalData.createData()
end

return LocalData
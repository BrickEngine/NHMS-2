local PlayerDataHelper = {}

local data = {} :: {[Player]: {[string]: any}}

function PlayerDataHelper.getPlrData(plr: Player, ind: string): any 
    if (not data[plr]) then
        warn(`No data of {plr.UserId} found`); return false
    end
    if (not data[plr][ind]) then
        warn(`No data of {plr.UserId} with index {ind} found`); return false
    end

    return data[plr][ind]
end

function PlayerDataHelper.setPlrData(plr: Player, ind: string, val: any)
    if (not data[plr]) then
        warn(`No data of {plr.UserId} found`); return
    end
    if (not data[plr][ind]) then
        warn(`No data of {plr.UserId} with index {ind} found`); return
    end

    data[plr][ind] = val
end

function PlayerDataHelper.createPlrData(plr: Player, plrData: {[string]: any})
    if (not data[plr]) then
        data[plr] = {}
    end
    PlayerDataHelper.clearPlrData(plr)
    data[plr] = plrData
end

function PlayerDataHelper.clearPlrData(plr: Player)
    if (data[plr]) then
        for _, v: any in pairs(data[plr]) do
            v = nil
        end
        data[plr] = nil
    end
end

return PlayerDataHelper
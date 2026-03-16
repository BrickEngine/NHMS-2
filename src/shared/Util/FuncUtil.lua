local FuncUtil = {}

--[[
    Creates a deep-copy of a table
    @param tbl - table to create a deep-copy of
]]
function FuncUtil.deepCopy(tbl: {[any]: any}): {[any]: any}
    local new = {}
    for k, v in pairs(tbl) do
        if (type(v) == "table") then
            new[k] = FuncUtil.deepCopy(v)
        else
            new[k] = v
        end
    end
    return new
end

return FuncUtil
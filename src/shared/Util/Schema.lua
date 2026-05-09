--[[
    Defines Schemas for unique data sets to simplify client-server validation.
]]

local Schema = {
    number = function(): (any) -> boolean
        return function(v)
            return typeof(v) == "number" 
        end
    end,

    boolean = function(): (any) -> boolean
        return function(v)
            return typeof(v) == "boolean" 
        end
    end,

    vector3 = function(): (any) -> boolean
        return function(v)
            return typeof(v) == "Vector3" 
        end
    end,

    vector2 = function(): (any) -> boolean
        return function(v)
            return typeof(v) == "Vector2" 
        end
    end,

    cFrame = function(): (any) -> boolean
        return function(v)
            return typeof(v) == "CFrame" 
        end
    end,

    numRange = function(min: number, max: number): (any) -> boolean
        return function(v)
            return typeof(v) == "number" and v >= min and v <= max
        end
    end,

    -- Makes a validator optional.
    -- Example: x = Schema.optional(Schema.number)
    optional = function(validator: (any) -> boolean): (any) -> boolean
        return function(v) return v == nil or validator(v) end
    end
}

--[[
    Validates a data-set (table) of schemas
    @return success
    @return error message
]]
function Schema.validate(params: any, schema: {[string]: (any) -> boolean}): (boolean, string?)
    if (typeof(params) ~= "table") then
        return false, "params not a table"
    end

    for ind: string, check: (any) -> boolean in schema do
        local value = params[ind]
        if not check(value) then
            return false, `invalid field '{ind}'`
        end
    end

    return true
end


return Schema
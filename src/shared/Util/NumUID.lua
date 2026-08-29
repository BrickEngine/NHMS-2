--!strict

--[[
    Helper module for creating and managing object bound UIDs.
]]

local function createIdTbl(amount: number): {number}
    assert(amount > 0, "amount must be > 0")
    local arr = {}
    for i=amount, 1, -1 do
        arr[#arr + 1] = i
    end
    return arr
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local NumUID = {}
NumUID.__index = NumUID

export type NumUID = {
    assigned: {[number]: any?},
    occ: {[number]: boolean},
    free: {number},

    new: (number) -> NumUID,

    alloc: (self: NumUID, any?) -> number,
    forceAlloc: (self: NumUID, number) -> (),
    release: (self: NumUID, number) -> boolean,
    forceRelease: (self: NumUID, number) -> (),
    isOccupied: (self: NumUID, number) -> boolean,
    assignObj: (self: NumUID, any, number) -> (),
    getObjById: (self: NumUID, number) -> any?,
}

--[[
	Creates a new numerical UID object for managing id objects
	@param amount - number of uids to make available
]]
function NumUID.new(amount: number): NumUID
    local self = setmetatable({}, NumUID)

    self.assigned = {} :: {[number]: any?}
    self.occ = {} :: {[number]: boolean}
    self.free = createIdTbl(amount)

    -- coroutine.wrap(function()
    --     while (task.wait(0.5)) do
    --         print("SERVER: ", RunService:IsServer(), " --- ", self.assigned) 
    --     end
    -- end)()

    return self :: any
end

--[[
	Allocates the next available UID and returns it
	@return id
]]
function NumUID:alloc(): number
    local id = table.remove(self.free) :: number
    if (self.occ[id]) then
        error(`Id '{id}' was already allocated`)
    end
    self.occ[id] = true

    return id
end

--[[
	Allocates a specific UID without checking whether its free or not;
    should be called by the client only to apply server-side allocations
]]
function NumUID:forceAlloc(id: number)
    if (self.occ[id]) then
        warn(`Overwritten id '{id}'`)
    end
    self.occ[id] = true
end

--[[
	Assigns an object to a given ID
	@param obj - value to assign
    @param id - the uid
]]
function NumUID:assignObj(obj: any, id: number)
    if (not self.occ[id]) then
        error(`Given uid '{id}' has not been allocated`)
    end
    self.assigned[id] = obj
end

--[[
	Frees a given UID by reassigning it to the free table, does NOT destroy the assigned object
	@param id - the uid
	@return success
]]
function NumUID:release(id: number): boolean
    if (self.occ[id]) then
        -- remove assigned object
        if (self.assigned[id]) then
            self.assigned[id] = nil
        end
        self.occ[id] = nil
        self.free[#self.free + 1] = id
        return true
    end
    return false
end

--[[
	Frees a given UID without changing the free table;
    should be called by the client only to mirror server-side changes
	@param id - the uid
	@return success
]]
function NumUID:forceRelease(id: number)
    self.occ[id] = nil
end

--[[
	Checks whether a UID is currently in use
	@param id - the uid
	@return occupied
]]
function NumUID:isOccupied(id: number): boolean
    return self.occ[id] ~= nil
end

--[[
	Gets object from UID
	@param id - the uid
	@return object or nil
]]
function NumUID:getObjById(id: number): any?
    return self.assigned[id]
end

return NumUID
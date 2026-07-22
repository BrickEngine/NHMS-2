--[[
    Creates class objects for managing multiple instances for one reference sound object
]]

export type Object = {
    mdl: Model,
    refSound: Sound,
    size: number,
    currIndex: number, 
    sounds: {Sound},

    play: (self: Object) -> (),
    getRefSound: (self: Object) -> Sound,
    getCurrentSound: (self: Object) -> Sound,
    destroy: (self: Object) -> (),
}

local SoundAcc = {}
SoundAcc.__index = SoundAcc

function SoundAcc.new(mdl: Model, refSound: Sound, accSize: number): Object
    local self = setmetatable({}, SoundAcc)

    local sndRootPart = mdl.PrimaryPart
    assert(accSize >= 1, "Accumulator size must be at least 1")
    assert(sndRootPart, "Mdl must have a primary part")

    self.mdl = mdl
    self.refSound = refSound
    self.size = accSize
    self.currIndex = 1
    self.sounds = {} :: {Sound}

    for i=1, accSize, 1 do
        local soundCopy = refSound:Clone()
        soundCopy.Parent = sndRootPart
        self.sounds[i] = soundCopy
    end
    refSound.Parent = sndRootPart

    return self
end

function SoundAcc:play()
    local currIndex = self.currIndex :: number
    local accSound = self.sounds[currIndex] :: Sound

    accSound:Play()
    
    currIndex += 1
    if (currIndex > self.size) then
        currIndex = 1
    end
    self.currIndex = currIndex
end

function SoundAcc:getRefSound(): Sound
    return self.refSound
end

function SoundAcc:getCurrentSound(): Sound
    return self.sounds[self.currentIndex]
end

function SoundAcc:destroy()
    for i,s: Sound in ipairs(self.sounds :: {Sound}) do
        s:Destroy()
        self.sounds[i] = nil
    end
    (self.refSound :: Sound):Destroy()
end

return SoundAcc
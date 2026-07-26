--[[
    Creates class objects for managing multiple instances for one reference sound object
]]

export type Object = {
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

--[[
    Creates a sound acc from a given referece sound instance.
    All created sounds are parented to the same instance the ref sound is parented to.
    @param refSound - reference / template sound object
    @param accSize - how many sounds to create
]]
function SoundAcc.new(refSound: Sound, accSize: number): Object
    local self = setmetatable({}, SoundAcc)

    assert(accSize >= 1, "Accumulator size must be at least 1")
    assert(refSound.Parent ~= nil, "refSound requires a parent")

    self.refSound = refSound
    self.size = accSize
    self.currIndex = 1
    self.sounds = {} :: {Sound}

    for i=1, accSize, 1 do
        local soundCopy = refSound:Clone()
        soundCopy.Parent = refSound.Parent
        self.sounds[i] = soundCopy
    end

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

function SoundAcc:getParentInst(): Instance
    local sound: Sound = self.refSound
    if (not sound.Parent) then
        error("Sound has no parent")
    end
    return sound.Parent
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
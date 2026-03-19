-- Init module for character controller

local Simulation = require(script.Simulation)
local Camera = require(script.Camera)

local Controller = {}
Controller.__index = Controller

function Controller.init()
    local self = setmetatable({}, Controller)

    self.simulation = Simulation :: Simulation.Simulation
    self.camera = Camera

    return self
end

function Controller:getSimulation(): Simulation.Simulation
    return self.simulation
end

function Controller:getCamera(): Camera.CameraModule
    return self.camera
end

return Controller.init()
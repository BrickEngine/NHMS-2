--[[
    Helper module for managing objects with paticle emitters.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WATER_SPLASH_DEL_DELAY = 5

local VEC3_ZERO = Vector3.zero

local sfxFold = ReplicatedStorage.Assets.SFX

local ParticleEffects = {}

function ParticleEffects.summonWaterSplash(pos: Vector3, vel: Vector3?)
    local wsRoot = sfxFold.Other.WaterSplash:Clone()
    wsRoot.Parent = Workspace
    wsRoot.Anchored = true
    wsRoot.Position = pos

    local v = vel or VEC3_ZERO
    local splashVel = Vector3.new(v.X, -v.Y * 0.5, v.Z)
    wsRoot.AssemblyLinearVelocity = splashVel

    local emitCount = 6
    if (v.Magnitude > 40) then
        emitCount = 8
    end

    for _, pEmitter: ParticleEmitter in pairs(wsRoot:GetChildren()) do
        pEmitter.Enabled = false
        pEmitter:Emit(emitCount)
    end

    task.delay(
        WATER_SPLASH_DEL_DELAY,
        function() wsRoot:Destroy() end
    )
end

return ParticleEffects
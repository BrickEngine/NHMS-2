--[[
    Helper module for managing objects with paticle emitters.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WATER_SPLASH_DEL_DELAY = 5

local VEC3_ZERO = Vector3.zero

local sfxFold = ReplicatedStorage.Assets.SFX

export type EntityInfo = {
    cf: CFrame,
    vel: Vector3,
    exit: boolean
}

------------------------------------------------------------------------------------------------------------------------
local ParticleEffects = {}

function ParticleEffects.summonWaterSplash(pos: Vector3, vel: Vector3?)
    local waterSplashPart = sfxFold.Other.WaterSplash:Clone()
    waterSplashPart.Parent = Workspace
    waterSplashPart.Anchored = true
    waterSplashPart.Position = pos

    local v = vel or VEC3_ZERO
    local splashVel = Vector3.new(v.X, -v.Y * 0.5, v.Z)
    waterSplashPart.AssemblyLinearVelocity = splashVel

    local emitCount = 6
    if (v.Magnitude > 40) then
        emitCount = 8
    end

    for _, pEmitter: ParticleEmitter in pairs(waterSplashPart:GetChildren()) do
        pEmitter.Enabled = false
        pEmitter:Emit(emitCount)
    end

    task.delay(
        WATER_SPLASH_DEL_DELAY,
        function() waterSplashPart:Destroy() end
    )
end

function ParticleEffects.createDirSparksUpdater(
    eInfo: EntityInfo, lockToPart:boolean, spreadVec: Vector2, offset: Vector3?
)
    local dSparkPart = sfxFold.Explosions.DirSparks:Clone()
    local sparks: ParticleEmitter = dSparkPart.Attachment.Sparks
    dSparkPart.Parent = Workspace
    dSparkPart.Anchored = true
    sparks.VelocityInheritance = 1
    sparks.LockedToPart = lockToPart
    sparks.SpreadAngle = spreadVec
    sparks.Enabled = true

    local offsetVec = offset and offset or VEC3_ZERO

    local updateConn: RBXScriptConnection
    updateConn = RunService.RenderStepped:Connect(function(dt: number)
        if (eInfo.exit) then
            dSparkPart:Destroy()
            updateConn:Disconnect()
        end

        local flatVel = Vector3.new(eInfo.vel.X, 0, eInfo.vel.Z)

        dSparkPart.Position = eInfo.cf.Position + offsetVec
        if (flatVel.Magnitude > 0.001) then
            dSparkPart.CFrame = CFrame.lookAt(
                dSparkPart.Position, dSparkPart.Position + flatVel.Unit
            )
        end
        dSparkPart.AssemblyLinearVelocity = eInfo.vel
    end)
end

return ParticleEffects
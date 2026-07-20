--[[
    Manages visual effects and animations for local and global character instances.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
--local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)
local Animation = require(ReplicatedStorage.Shared.Util.Animation)

local ANIM_THRESHHOLD = 0.5 -- studs/s
local ANIM_SPEED_FAC = 0.025

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local PlayerVisuals = {
    character = nil :: Model?,
    animation = nil :: Animation.Module?
}

function PlayerVisuals.init()
    local function onCharAdded(character: Model)
        if (PlayerVisuals.animation :: Animation.Module) then
            PlayerVisuals.animation.destroy()
        end
        PlayerVisuals.character = character
        PlayerVisuals.animation = Animation.new(PlayerVisuals.character)

        RunService.PreAnimation:Connect(PlayerVisuals.animUpdate)
    end

    if (PlayerVisuals.character) then
        onCharAdded(PlayerVisuals.character)
    end
    Players.LocalPlayer.CharacterAdded:Connect(onCharAdded)
end

function PlayerVisuals.setAnimStates()
    local simData = ClientRoot.getSimData()
    local charPrimPart = PlayerVisuals.character.PrimaryPart
    local anim = PlayerVisuals.animation
    if (not charPrimPart) then
        warn("Missing PimraryPart of character"); return
    end
    local horiVelVec = Vector3.new(charPrimPart.AssemblyLinearVelocity.X, 0 ,charPrimPart.AssemblyLinearVelocity.Z)

    if (simData.isGrounded) then
        if (horiVelVec.Magnitude > ANIM_THRESHHOLD) then
            anim:setState(Animation.AnimationStateId.WALK)
            anim:adjustSpeed(horiVelVec.Magnitude * ANIM_SPEED_FAC)
        else
            anim:setState(Animation.AnimationStateId.IDLE)
            anim:adjustSpeed(1)
        end
    elseif (simData.inWater) then
        anim:setState(Animation.AnimationStateId.WALK)
        anim:adjustSpeed(1)
    else
        anim:setState(Animation.AnimationStateId.IDLE)
        anim:adjustSpeed(1)
    end
end

function PlayerVisuals.animUpdate(dt: number)
    PlayerVisuals.setAnimStates()
end

function PlayerVisuals:update(dt: number)
    
end

return PlayerVisuals
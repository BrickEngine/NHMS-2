local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

-- local ClientRoot
-- if (RunService:IsClient()) then
--     ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
-- end

-- dyn offset
local ENABLE_Y_OFFS = true
local MAX_MOUSE_X_DIST = 0.325
local MAX_SPRING_Y_DIFF = 0.2
local MOUSE_X_FAC = 0.0065
local Y_DIFF_FAC = 0.0055
local DYN_OFFS_LERP_FAC = 45

local VEC3_UP = Vector3.new(0, 1, 0)
local VEC3_RIGHT = Vector3.new(1, 0, 0)

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local WeaponCommon = {}

function WeaponCommon.joinWeaponToOwnerPrimPart(weaponMdl: Model, ownerMdl: Model)
    local joint = Instance.new("Motor6D", weaponMdl.PrimaryPart)
    joint.Name = "WeaponM6D"
    joint.Part0 = ownerMdl.PrimaryPart
    joint.Part1 = weaponMdl.PrimaryPart

    return joint
end

--[[
    Welds and unanchors the weapon model to a player character's primary part.
    This is useful when equipping weapons for 
    @param mdl - character Model
    @param weapMdl - weapon Model
    @param offsetPos - offset of weapMdl from mdl
]]
function WeaponCommon.weldWeaponModel(mdl: Model, weapMdl: Model, offsetPos: CFrame)
    assert(weapMdl.PrimaryPart, "Missing PrimaryPart of weapon model")
    assert(mdl.PrimaryPart, "Missing PrimaryPart of character model")

    for _, p: Instance in pairs(weapMdl:GetChildren()) do
        if (p:IsA("BasePart")) then
            p.Anchored = false
        end
    end

    weapMdl.PrimaryPart.CFrame = mdl.PrimaryPart.CFrame * offsetPos

    local weldConst = Instance.new("WeldConstraint", weapMdl.PrimaryPart)
    weldConst.Name = "WeapToBodyWeld"
    weldConst.Part0 = weapMdl.PrimaryPart
    weldConst.Part1 = mdl.PrimaryPart
end

local lastYVel = 0
local lastYDiff = 0
local lastMouseX = 0

WeaponCommon.dynOffset = {
    --[[
        Sets last offset values to 0.
    ]]
    reset = function()
        lastYVel = 0
        lastYDiff = 0
        lastMouseX = 0
    end,

    --[[
        Calculates vertical and horizontal weapon offset relative to player movement;
        mouse movement delta is used to calculate the horizonal component.
        @param dt - update time delta
        @param vel - character primary part velocity
        @param baseCFOffset - base weapon offset CFrame
        @param dirVec - Vector3 which determines the corrected vertical dir
    ]]
    apply = function(dt: number, vel: Vector3, baseCFOffset: CFrame): CFrame
        if (not RunService:IsClient()) then
            error("Can only be executed by client")
        end

        local mouseX = UserInputService:GetMouseDelta().X
        lastMouseX = MathUtil.flerp(lastMouseX, mouseX, dt * DYN_OFFS_LERP_FAC)
        mouseX = MathUtil.flerp(lastMouseX, 0, dt * DYN_OFFS_LERP_FAC)
        local horiPos = math.clamp(lastMouseX * -MOUSE_X_FAC, -MAX_MOUSE_X_DIST, MAX_MOUSE_X_DIST)

        local vertPos
        if (ENABLE_Y_OFFS) then
            local yDiff = (lastYVel - vel.Y) * Y_DIFF_FAC
            vertPos = MathUtil.dSpring(0, 0, lastYDiff, 0.5, dt)
            vertPos = math.clamp(vertPos, -MAX_SPRING_Y_DIFF * 1.8, MAX_SPRING_Y_DIFF)

            lastYVel = MathUtil.flerp(lastYVel, vel.Y, dt * 7.5)
            lastYDiff = MathUtil.flerp(lastYDiff, yDiff, dt * 50)
        else
            vertPos = 0
        end

        local newCFOffset = baseCFOffset:ToObjectSpace(
            baseCFOffset * CFrame.new(VEC3_UP * vertPos) 
            * CFrame.new(VEC3_RIGHT * horiPos)
        )

        return baseCFOffset * newCFOffset
    end
}


return WeaponCommon
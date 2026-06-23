local MouseService = game:GetService("MouseService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

local ClientRoot
if (RunService:IsClient()) then
    ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
end

local MAX_MOUSE_X_DIST = 0.325
local MAX_SPRING_Y_DIFF = 0.2
local MOUSE_X_FAC = 0.0065
local Y_DIFF_FAC = 0.0055

local VEC3_UP = Vector3.new(0, 1, 0)
local VEC3_RIGHT = Vector3.new(1, 0, 0)

local lastYVel = 0
local lastMouseX = 0
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

function WeaponCommon.equipWeaponModelGlobal(mdl: Model, offsetPos: CFrame)

end

--TODO: convert to a table with functions reset, calc and setEnabled
--[[
    Calculates addition weapon offset dependent on vertical and horizontal character movement;
    mouse movement delta is used to calculate the horizonal component.
    @param dt - update time delta
    @param vel - character primary part velocity
    @param baseCFOffset - base weapon offset CFrame
    @param dirVec - Vector3 which determines the corrected vertical dir
]]
function WeaponCommon.calcVelImpactOffsetCFrame(
    dt: number, vel: Vector3, baseCFOffset: CFrame
): CFrame
    if (not RunService:IsClient()) then
        error("Can only be executed by client")
    end

    local mouseX = UserInputService:GetMouseDelta().X
    lastMouseX = MathUtil.lerp(lastMouseX, mouseX, dt * 25)
    local horiPos = math.clamp(lastMouseX * MOUSE_X_FAC, -MAX_MOUSE_X_DIST, MAX_MOUSE_X_DIST)

    local yDiff = (lastYVel - vel.Y) * Y_DIFF_FAC
    local vertPos = MathUtil.dSpring(0, 0, yDiff, 0.5, dt)
    vertPos = math.clamp(vertPos, -MAX_SPRING_Y_DIFF * 1.8, MAX_SPRING_Y_DIFF)
    --springPos = math.clamp(springPos, -VEL_IMPACT_MAX_OFFS, VEL_IMPACT_MAX_OFFS)

    local newCFOffset = baseCFOffset:ToObjectSpace(
        baseCFOffset * CFrame.new(VEC3_UP * vertPos) 
        * CFrame.new(VEC3_RIGHT * horiPos)
    )
    lastYVel = MathUtil.lerp(lastYVel, vel.Y, dt * 7.5)

    return baseCFOffset * newCFOffset
end


return WeaponCommon
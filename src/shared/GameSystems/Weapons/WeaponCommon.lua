local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)

local MAX_SPRING_Y_DIFF = 0.2
local Y_DIFF_FAC = 0.0085
local PHYS_DT = 0.05
local VEC3_ZERO = Vector3.new(0, 0, 0)

local lastYVel = 0
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

--TODO: add mouse delta
--[[
    Calculates addition weapon offset dependent on vertical and horizontal character movement;
    mouse movement delta is used to calculate the horizonal component.
    @param dt - update time delta
    @param vel - character primary part velocity
    @param baseCFOffset - base weapon offset CFrame
    @param dirVec - Vector3 which determines the corrected vertical dir
]]
function WeaponCommon.calcVelImpactOffsetCFrame(
    dt: number, vel: Vector3, baseCFOffset: CFrame, dirVec: Vector3
): CFrame
    local yDiff = (lastYVel - vel.Y) * Y_DIFF_FAC
    --local dir = (vel.Y >= 0) and -1 or 1
    -- local vertFinalOffs = math.clamp(
    --     yDiff * dir * VEL_IMPACT_MULT, 
    --     -VEL_IMPACT_MAX_OFFS, VEL_IMPACT_MAX_OFFS
    -- )
    -- lastYOffset = MathUtil.lerp(lastYOffset, vertFinalOffs, dt * 25)

    -- local newVelCFOffset = baseCFOffset:ToObjectSpace(
    --     baseCFOffset * CFrame.new(dirVec * lastYOffset)
    -- )
    -- lastYVel = MathUtil.lerp(lastYVel, 0, dt * 15)

    --lastYDiff = MathUtil.lerp(lastYDiff, yDiff, dt)

    local springPos = MathUtil.dSpring(0, 0, yDiff, 0.5, dt)
    springPos = math.clamp(springPos, -MAX_SPRING_Y_DIFF * 1.8, MAX_SPRING_Y_DIFF)
    --springPos = math.clamp(springPos, -VEL_IMPACT_MAX_OFFS, VEL_IMPACT_MAX_OFFS)

    local vertCFOffset = baseCFOffset:ToObjectSpace(
        baseCFOffset * CFrame.new(dirVec * springPos)
    )

    --TODO: lerp pos val to 0 from direct 
    --lastVelCFOffset = lastVelCFOffset:Lerp(newVelCFOffset, dt * 10)
    lastYVel = MathUtil.lerp(lastYVel, vel.Y, dt * 10)

    return baseCFOffset * vertCFOffset
end


return WeaponCommon
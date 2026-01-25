local VEC3_ZERO = Vector3.zero

local PhysUtil = {}

function PhysUtil.getModelMass(mdl: Model, recurse: boolean?): number
    local totalMass = 0

    for _, inst: Instance in pairs(mdl:GetChildren()) do
        if (inst:IsA("BasePart")) then
            totalMass += inst.Mass
        elseif (recurse and inst:IsA("Model")) then
            totalMass += PhysUtil.getModelMass(inst)
        end
    end
    return totalMass
end

-- Get the mass of a model's part assembly with only the given tag
function PhysUtil.getModelMassByTag(mdl: Model, tag: string, recurse: boolean?): number
    local totalMass = 0

    for _, inst: Instance in pairs(mdl:GetChildren()) do
        if (inst:IsA("BasePart") and inst:HasTag(tag)) then
            totalMass += inst.Mass
        elseif (recurse and inst:IsA("Model")) then
            totalMass += PhysUtil.getModelMass(inst)
        end
    end
    return totalMass
end

function PhysUtil.unanchorModel(mdl: Model)
    for _, inst in pairs(mdl:GetDescendants()) do
        if (inst:IsA("BasePart")) then
            inst.Anchored = false
        elseif (inst:IsA("Model")) then
            PhysUtil.unanchorModel(inst)
        end
    end
end

-- Calculate accel based on displacement and current vel of assembly
function PhysUtil.accelFromDispl(posDiff: number, vel: number, downForce: number, dt: number)
    return downForce + (2*(posDiff - vel*dt))/(dt*dt)
end

--[[
    Substep for stable acceleration prediction at low framerates (high dt)
    - initial accel calculated with PhysUtil.forceFromDisplacementVec3
    - downForce should be positive
]]
function PhysUtil.substepAccel(
        vel: number, pos: number, targetPos: number, downForce: number, numSteps: number, dt: number
    ): (number, number, number)

    local accel = PhysUtil.accelFromDispl((targetPos-pos), vel, downForce, dt)

    local stepAccel = accel
    local stepVel = vel
    local stepPos = pos
    local t = dt / numSteps

    for i=1, numSteps-1, 1 do
        local stepNetAccel = stepAccel - downForce

        local predVel: number = stepNetAccel*t
        local predPosDisp: number = (vel*t) + (0.5*predVel*t)
        local predAccel: number = downForce + 2*((targetPos - (stepPos + predPosDisp) - stepVel*t) / t*t)

        stepAccel = (accel + predAccel) * 0.5
        stepVel = (predVel + vel) * 0.5
        stepPos = (predPosDisp + pos) * 0.5
    end

    return stepAccel, stepVel, stepPos
end

function PhysUtil.stepperVec3(
        pos: Vector3, vel: Vector3, targetPos: Vector3, stiffness: number, damping: number,precision: number, dt: number
    ): (Vector3, Vector3)

    local force = -stiffness*(pos - targetPos)
    local dampForce = damping*vel
    local accel = force - dampForce

    local stepVel = vel*accel*dt
    local stepPos = pos*vel*dt

    if ((stepVel.Magnitude < precision) and ((targetPos - stepPos).Magnitude < precision)) then
        return targetPos, VEC3_ZERO
    end
    return stepPos, stepVel
end

return PhysUtil
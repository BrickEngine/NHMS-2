-- Various utility functions involving vectors and numbers

local DEFAULT_RATE = 0.5 -- balanced, as all things should be

local MathUtil = {}

-- Standard lerp function;
-- v0: current, v1: target, dt: time delta
function MathUtil.lerp(v0: number, v1: number, dt: number): number
	-- if (math.abs(v1 - v0) < 0.1) then
	-- 	return v1
	-- end
	return (1 - dt) * v0 + dt * v1
end

-- v0: current, v1: target, dt: time delta
function MathUtil.easeOutQuad(v0: number, v1: number, dt: number): number
    return -(v1 - v0) * dt * (dt - 2) + v0
end

-- Framerate independent lerp function; slightly less efficient than lerp;
-- v0: current, v1: target, r: rate (value between 0 and 1), dt: time delta
function MathUtil.flerp(v0: number, v1: number, dt: number, r: number?): number
	local _r = r
    if (not _r) then
        _r = DEFAULT_RATE
    end
	return MathUtil.lerp(v0, v1, 1 - math.pow(_r, dt))
end

-- Standard lerp for each value of the Vector3;
-- vec0: current, vec1: target, r: rate (value between 0 and 1), dt: time delta
function MathUtil.vec3Lerp(vec0: Vector3, vec1: Vector3, dt:number): Vector3
	return Vector3.new(
		MathUtil.lerp(vec0.X, vec1.X, dt),
		MathUtil.lerp(vec0.Y, vec1.Y, dt),
		MathUtil.lerp(vec0.Z, vec1.Z, dt)
	)
end

-- Framerate independent lerp for each value of the Vector3;
-- vec0: current, vec1: target, r: rate (value between 0 and 1), dt: time delta
function MathUtil.vec3Flerp(vec0: Vector3, vec1: Vector3, dt: number, r: number?): Vector3
	return Vector3.new(
		MathUtil.flerp(vec0.X, vec1.X, dt, r),
		MathUtil.flerp(vec0.Y, vec1.Y, dt, r),
		MathUtil.flerp(vec0.Z, vec1.Z, dt, r)
	)
end

-- Clamps each value of the Vector3, equivalent to math.clamp
function MathUtil.vec3Clamp(vec: Vector3, vMin: Vector3, vMax: Vector3): Vector3
	return Vector3.new(
		math.clamp(vec.X, vMin.X, vMax.X),
		math.clamp(vec.Y, vMin.Y, vMax.Y),
		math.clamp(vec.Z, vMin.Z, vMax.Z)
	)
end

-- Project a Vector onto a plane with given plane normal
function MathUtil.projectOnPlaneVec3(v: Vector3, norm: Vector3): Vector3
    local sqrMag = norm:Dot(norm)
    if (sqrMag < 0.01) then
        return v
    end
    local dot = v:Dot(norm)
    return Vector3.new(
        v.X - norm.X * dot / sqrMag,
        v.Y - norm.Y * dot / sqrMag,
        v.Z - norm.Z * dot / sqrMag
    )
end

return MathUtil
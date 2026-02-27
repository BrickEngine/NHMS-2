local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugVisualize = require(script.Parent.DebugVisualize)
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)

-- [[checkFloor]]

-- number of rays to cast
local NUM_GND_RAYS = 64
-- inward offset of the boundary for the outermost rays
local RADIUS_OFFSET = 0.08
-- ray origin offset from the default hip height
local RAY_Y_OFFSET = 0.1
 -- in rad, angle at which a hit will not be registered
local MAX_INCLINE_ANGLE = math.rad(70)

-- [[checkWall]]

-- number of rays to cast
local NUM_WALL_RAYS = 12
-- ray origin offset from the character's lowest position
local LEG_OFFSET = 1.0
-- range of the rays
local WALL_RANGE = 2.95 --3.45
-- max distance between ordered hit points which, if exceeded, will force the target position to be
-- evaluated differently for ground detection
local MAX_GND_POINT_DIFF = 0.25
 -- if true, picks highest point as target position
local TARGET_CLOSEST = true
-- whether to only register wall proximity when multiple rays successfully hit
local REQUIRE_MIN_RAYS = false
local MIN_REGISTER_RAYS = 4
-- determines which coll group to use for wall detection (false = default)
local USE_WALL_COLL_GROUP = true

-- [[checkWater]]

-- toggle for how the BuoyancySensor detects water
local BUOY_FULLY_SUBMERGED = false

-- [[Misc]]

local PHI = 1.61803398875
local BOUND_POINTS = math.round(2 * math.sqrt(NUM_GND_RAYS))
local VEC3_ZERO = Vector3.zero
local VEC3_UP = Vector3.new(0, 1 ,0)
local VEC3_FARDOWN = -999999999 * VEC3_UP

local floorRayParams = RaycastParams.new()
floorRayParams.CollisionGroup = CollisionGroup.PLAYER
floorRayParams.FilterType = Enum.RaycastFilterType.Exclude
floorRayParams.IgnoreWater = true

local wallRayParams = RaycastParams.new()
wallRayParams.CollisionGroup = CollisionGroup.PLAYER
wallRayParams.FilterType = Enum.RaycastFilterType.Exclude
wallRayParams.IgnoreWater = true

local waterRayParams = RaycastParams.new()
waterRayParams.CollisionGroup = CollisionGroup.PLAYER
waterRayParams.FilterType = Enum.RaycastFilterType.Exclude
waterRayParams.IgnoreWater = false

------------------------------------------------------------------------------------------------------------------------

local function radiusDist(k: number, n: number, b: number)
	if (k > n-b) then
		return 1
	else
		return math.sqrt(k - 0.5) / math.sqrt(n - (b + 1)/2)
	end
end

-- Calculates a virtual plane normal from given points
local function avgPlaneFromPoints(ptsArr: {Vector3}) : {centroid: Vector3, normal: Vector3}
	local n = #ptsArr
	local noPlane = {
			centroid = VEC3_ZERO,
			normal = VEC3_UP
		}
	if (n < 3) then
		warn("No plane exists")
		return noPlane
	end

	local sum = VEC3_ZERO
	for i,vec: Vector3 in ipairs(ptsArr) do
		sum += vec
	end
	local centroid = sum / n

	local xx, xy, xz, yy, yz, zz = 0, 0, 0, 0, 0, 0
	for i,vec: Vector3 in ipairs(ptsArr) do
		local r : Vector3 = vec - centroid
		xx += r.X * r.X
		xy += r.X * r.Y
		xz += r.X * r.Z
		yy += r.Y * r.Y
		yz += r.Y * r.Z
		zz += r.Z * r.Z
	end
	local det_x = yy*zz - yz*yz
    local det_y = xx*zz - xz*xz
    local det_z = xx*yy - xy*xy

	local det_max = math.max(det_x, det_y, det_z)
	if (det_max <= 0) then
		return noPlane
	end

	local dir: Vector3 = VEC3_ZERO
	if (det_max == det_x) then
		dir = Vector3.new(det_x, xz*yz - xy*zz, xy*yz - xz*yy)
	elseif (det_max == det_y) then
		dir = Vector3.new(xz*yz - xy*zz, det_y, xy*xz - yz*xx)
	else
		dir = Vector3.new(xy*yz - xz*yy, xy*xz - yz*xx, det_z)
	end

	-- Invert normal, if upside down
	if (dir:Dot(VEC3_UP) < 0) then
		dir = -dir
	end

	return {
		centroid = centroid,
		normal = dir.Unit
	}
end

local function avgVecFromVecs(vecArr: {Vector3}): Vector3
	local n = #vecArr
	-- If there is no data, default to a horizontal plane
	if (n == 0) then
		warn("Empty vector array")
		return VEC3_UP
	elseif (n == 1) then
		return vecArr[1]
	end

	local vecSum = VEC3_ZERO
	for _,v in ipairs(vecArr) do
		vecSum += v
	end

	return (vecSum * 1/n)
end

-- Finds the biggest numerical difference between two adjacent numbers in an ordered array
local function biggestOrderedDist(numArr: {number}): number
	local arr = numArr
	table.sort(numArr, function(a0: number, a1: number): boolean 
		return a0 < a1
	end)

	local i = 1
	local max = 0
	while (i < #arr) do
		local dist = math.abs(arr[i] - arr[i + 1]) 
		max = (dist > max) and dist or max
		i += 1
	end

	return max
end

local function lineDist(radius: number, point: number, n: number): number
	return (radius / n) * (1 + 2 * point)
end

-- Finds the biggest difference 
local function biggestVecAngleDiff(vecArr: {Vector3}): number
	local maxAng = 0
	local arr = vecArr

	for i, vec: Vector3 in ipairs(arr) do
		arr[i] = vec.Unit
	end

	for i=1, #arr-2, 1 do
		for j=i+1, #arr-1, 1 do
			local dot = arr[i]:Dot(arr[j])

			-- compensate for rounding errors
			if (dot > 1) then dot = 1.0 end
			if (dot < -1) then dot = -1.0 end

			maxAng = math.max(math.acos(dot), maxAng)
		end
	end

	return maxAng
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------
local PhysCheck = {}

export type groundData = {
	grounded: boolean,
	pos: Vector3,
	closestPos: Vector3,
	normal: Vector3,
	gndHeight: number,
	normalAngle: number
}

export type wallData = {
	nearWall: boolean,
	normal: Vector3,
	position: Vector3,
	bankAngle: number,
	maxAngleDiff: number
}

type wallSide = {
	posArr: {Vector3},
	normalsArr: {Vector3}
}

export type waterData = {
	inWater: boolean,
	fullSubmerged: boolean,
	waterSurfacePos: Vector3
}


------------------------------------------------------------------------------------------------------------------------
-- Ground
------------------------------------------------------------------------------------------------------------------------

-- Cylindrical raycast operation for detailed ground proximity data
function PhysCheck.checkFloor(
	rootPos: Vector3,
	maxRadius: number,
	hipHeight: number,
	gndClearDist: number,
	rayParams: RaycastParams?
): groundData

	local grounded = false
	local closestPos = VEC3_FARDOWN
	local closestDist = math.huge
	local targetPos = VEC3_FARDOWN
    local targetNorm = VEC3_UP
    local targetNormAngle = 0
	local numHits = 0
	local numTotalHits = 0
	local adjHipHeight = hipHeight + RAY_Y_OFFSET
	local _rayParams = rayParams or floorRayParams

	-- Cylinder cast checks with sunflower distribution
	local hitPointsArr = {} :: {Vector3}
	local normalsArr = {} :: {Vector3}
	local ptsHeightArr = {} :: {number}

	-- TODO: return a hit BasePart, which is closest to the RootPart
	--local hitObjectArr = {} :: {BasePart}

	for i=1, NUM_GND_RAYS, 1 do
		local r = radiusDist(i, NUM_GND_RAYS, BOUND_POINTS) * (maxRadius - RADIUS_OFFSET)
		local theta = i * 360 * PHI
		local offsetX = r * math.cos(theta)
		local offsetZ = r * math.sin(theta)

		local ray = Workspace:Raycast(
			Vector3.new(
				rootPos.X + offsetX,
				rootPos.Y + RAY_Y_OFFSET,
				rootPos.Z + offsetZ
			),
			-VEC3_UP * adjHipHeight * 2,
			_rayParams
		)
		if (ray :: RaycastResult) then
			local debug_gnd_hit = false

			numTotalHits += 1
			normalsArr[numTotalHits] = ray.Normal

			if (ray.Distance <= adjHipHeight + gndClearDist) then

				local hitNormAng = math.asin((VEC3_UP:Cross(ray.Normal)).Magnitude)
				if (hitNormAng < MAX_INCLINE_ANGLE) then
					numHits += 1
					hitPointsArr[numHits] = ray.Position
					ptsHeightArr[numHits] = ray.Position.Y

					if (ray.Distance < closestDist) then
						closestDist = ray.Distance
						closestPos = ray.Position
					end
					debug_gnd_hit = true
				end
			end

			-- DEBUG
			if (DebugVisualize.enabled) then
				local gndRayColor
				if (debug_gnd_hit) then
					gndRayColor = Color3.new(0, 255, 0)
				else
					gndRayColor = Color3.new(255, 0, 0)
				end
				DebugVisualize.point(ray.Position, gndRayColor)
			end
		end
	end

	grounded = true

	if (TARGET_CLOSEST) then
		if (numHits > 0) then
			
			local biggestDist = biggestOrderedDist(ptsHeightArr)
			if (biggestDist <= MAX_GND_POINT_DIFF) then
				if (numHits >= 3) then
					targetPos = avgPlaneFromPoints(hitPointsArr).centroid
				elseif (numHits == 2) then
					targetPos = avgVecFromVecs(hitPointsArr)
				else
					targetPos = hitPointsArr[1]
				end
			else
				targetPos = closestPos
			end

			targetPos = closestPos
			targetNorm = avgVecFromVecs(normalsArr)
		else
			grounded = false
			targetNorm = VEC3_UP
		end

	else
		targetNorm = avgVecFromVecs(normalsArr)
		if (numHits > 2) then
			local planeData = avgPlaneFromPoints(hitPointsArr)
			targetPos = planeData.centroid
			targetNorm = planeData.normal
			--pNormAngle = math.deg(math.acos(targetNorm:Dot(VEC3_UP)))
		elseif (numHits == 2 or numHits == 1) then
			targetPos = avgVecFromVecs(hitPointsArr)
		else
			grounded = false
		end
	end

	targetNormAngle = math.asin((VEC3_UP:Cross(targetNorm)).Magnitude)
	--math.deg(math.acos(targetNorm:Dot(VEC3_UP)))

	DebugVisualize.normalPart(targetPos, targetNorm, Vector3.new(0.1, 0.1, 2))

	return {
        grounded = grounded,
		pos = targetPos,
		closestPos = closestPos,
		normal = targetNorm.Unit,
        gndHeight = targetPos.Y,
        normalAngle = targetNormAngle
    } :: groundData
end

------------------------------------------------------------------------------------------------------------------------
-- Wall
------------------------------------------------------------------------------------------------------------------------

-- To be used by the state machine modules when other checks require wall detection to be ignored
function PhysCheck.defaultWallData(): wallData
	return {
		nearWall = false,
		normal = VEC3_ZERO,
		position = VEC3_ZERO,
		bankAngle = 0,
		maxAngleDiff = 0
	}
end

-- Line based raycast checks for walls in a given direction
function PhysCheck.checkWall(
	rootPos: Vector3,
	direction: Vector3,
	maxRadius: number,
	hipHeight: number
): wallData

	assert(direction ~= VEC3_ZERO, "Direction vector must be non zero")

	local unitDir = Vector3.new(direction.X, 0, direction.Z).Unit
	local lineDir = unitDir:Cross(VEC3_UP)
	local lineStart = (rootPos + VEC3_UP * (LEG_OFFSET - hipHeight)) - lineDir * maxRadius
	local hitWallsSet = {} :: {[BasePart]: boolean}
	local hitWallsArr = {} :: {BasePart}
	local hitNormalsArr = {} :: {Vector3}
	local posArr = {} :: {Vector3}

	for i=0, NUM_WALL_RAYS - 1, 1 do
		local currPos =  lineStart + lineDir * lineDist(maxRadius, i, NUM_WALL_RAYS)
		local ray = Workspace:Raycast(currPos, unitDir * WALL_RANGE, waterRayParams) :: RaycastResult
		if (ray and ray.Instance and ray.Instance:IsA("BasePart")) then
			local hitPart = ray.Instance :: BasePart

			if (
				hitPart.CollisionGroup ==
				(USE_WALL_COLL_GROUP and CollisionGroup.WALL or CollisionGroup.DEFAULT)
			) then
				if (not hitWallsSet[ray.Instance]) then
					hitWallsSet[ray.Instance] = true
					hitWallsArr[#hitWallsArr + 1] = ray.Instance
				end
				hitNormalsArr[#hitNormalsArr + 1] = ray.Normal
				posArr[#posArr + 1] = ray.Position

				-- DEBUG
				if (DebugVisualize.enabled) then
					DebugVisualize.point(ray.Position, Color3.new(1, 0.5, 0))
				end
			end
		end

		-- DEBUG
		if (DebugVisualize.enabled) then
			DebugVisualize.point(currPos, Color3.new(0, 0, 1))
		end
	end

	if (#hitWallsArr == 0) then
		return PhysCheck.defaultWallData()
	end

	if (REQUIRE_MIN_RAYS) then
		if (#hitNormalsArr < MIN_REGISTER_RAYS) then
			return PhysCheck.defaultWallData()
		end
	end

	local normal = avgVecFromVecs(hitNormalsArr)
	local position = avgVecFromVecs(posArr)
	local bankAngle = math.acos(normal:Dot(VEC3_UP))
	local maxAngleDiff = biggestVecAngleDiff(hitNormalsArr)
	local nearWall = true

	-- Case: direction vector points away from wall (should rarely ever happen)
	if ((normal:Dot(unitDir) > 0)) then
		nearWall = false
	end

	return {
		nearWall = nearWall,
		normal = normal,
		position = position,
		bankAngle = bankAngle,
		maxAngleDiff = maxAngleDiff
	} :: wallData
end

------------------------------------------------------------------------------------------------------------------------
-- Water
------------------------------------------------------------------------------------------------------------------------

-- Line based raycast checks for walls in a given direction
function PhysCheck.checkWater(
	rootPos: Vector3,
	maxRadius: number,
	buoySens: BuoyancySensor
): waterData

	local surfacePos = math.huge
	local fullySubmerged = buoySens.FullySubmerged
	local inWater = (BUOY_FULLY_SUBMERGED) and fullySubmerged or buoySens.TouchingSurface
	
	local ray = Workspace:Spherecast(rootPos + VEC3_UP, maxRadius, -VEC3_UP * 2, waterRayParams)
	if (ray) then 
		if (ray.Material == Enum.Material.Water) then
			surfacePos = ray.Position
		end
	end

	return {
		inWater = inWater,
		fullSubmerged = fullySubmerged,
		waterSurfacePos = surfacePos
	} :: waterData
end

return PhysCheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugVisualize = require(script.Parent.DebugVisualize)
local Global = require(ReplicatedStorage.Shared.Global)

local NUM_RAYS = 7
local USE_COLL_GROUP = true -- determines, whether to treat all objects as walls
local RADIUS_OFFSET = 0.08
local RAY_Y_OFFSET = 0.1
local TARGET_CLOSEST = true -- if true, picks highest point as target position
local MAX_INCLINE_ANGLE = math.rad(70) -- convert to rad, angle at which a hit will not be registered

local PHI = 1.61803398875
local VEC3_ZERO = Vector3.zero
local ROOT_OFFSET = Vector3.new(0, -1.5, 0)

local rayParams = RaycastParams.new()
rayParams.CollisionGroup = USE_COLL_GROUP and Global.COLL_GROUPS.WALL or Global.COLL_GROUPS.DEFAULT

export type physData = {
	onWall: boolean,
	normal: Vector3,
	normalAngle: number
}

return function ()
	
end


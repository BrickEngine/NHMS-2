-- Default first person camera

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

--local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local Simulation = require(script.Parent.Parent.Simulation)
local CamInput = require(script.Parent.CamInput)
local BaseCam = require(script.Parent.BaseCam)
local MathUtil = require(ReplicatedStorage.Shared.Util.MathUtil)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)

local ROOT_OFFSET = Vector3.new(0, 2.5, 0)
local DEATH_OFFSET = Vector3.new(0, -3, 0)
local DEATH_ROT_CF_OFFSET = CFrame.fromEulerAnglesXYZ(math.rad(15), 0, math.rad(-60))
local DASH_OFFSET = Vector3.new(0, -1.8, 0)
local INP_SENS_FAC = 34	-- input sensitivity factor
local WALL_TILT = 5.5 -- deg - max cam wall tilt
local INP_TILT = 6 -- deg - max cam input based tilt
local TILT_DT = 0.2	-- time delta for tilt lerp functions
local DEATH_LERP_FAC = 5.45
local ROT_MIN_Y = -89 -- deg
local ROT_MAX_Y = 89 -- deg

local VEC3_ZERO = Vector3.zero

local simData = Simulation:getStateShared() :: Simulation.SharedVals

local lastCamOffs = VEC3_ZERO
local camAngVec = VEC3_ZERO
local lastWallTilt = 0
local lastInpTilt = 0

--------------------------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------------------------

local FPCam = setmetatable({}, BaseCam)
FPCam.__index = FPCam

export type FPCamModule = typeof(FPCam)

function FPCam.new()
	local self = setmetatable(BaseCam.new(), FPCam)

	self.switchToDeathCam = false
	self.lastUpdate = tick()

	return self
end

function FPCam:toggleDeathCam(toggle: boolean)
	self.switchToDeathCam = toggle
end

function FPCam:updateDeathCam(dt: number): (CFrame, CFrame)

	local now = tick()
	local cam = Workspace.CurrentCamera
	local camCFrame = cam.CFrame
	local camFocus = cam.Focus
	local rootPart: BasePart = self:getRootPart()

	if (rootPart) then
		camFocus = rootPart.CFrame
		lastCamOffs = MathUtil.vec3Flerp(lastCamOffs, DEATH_OFFSET, dt * DEATH_LERP_FAC)
		local targetRotCFrame = rootPart.CFrame.Rotation * DEATH_ROT_CF_OFFSET
		camCFrame =
			CFrame.new(camFocus.Position + (ROOT_OFFSET + lastCamOffs))
			* camCFrame.Rotation:Lerp(targetRotCFrame, dt * DEATH_LERP_FAC)
	end
	self.lastCameraTransform = camCFrame
	self.lastCameraFocus = camFocus

	self.lastUpdate = now
	return self.lastCameraTransform, self.lastCameraFocus
end

function FPCam:updateDashCam(dt: number)
	local effCamOffset = simData.isDashing and DASH_OFFSET or VEC3_ZERO
	lastCamOffs = MathUtil.vec3Clamp(
		MathUtil.vec3Flerp(lastCamOffs, effCamOffset, dt * 20), DASH_OFFSET, VEC3_ZERO
	)
end

function FPCam:updateWallCam(dt: number)
	local nearWall, rightSide = simData.nearWall, simData.isRightSideWall
	local fac = rightSide and -1 or 1
	local effCamTilt = 
		(nearWall and Simulation:getCurrentStateId() == PlayerStateId.WALL) and WALL_TILT or 0
	effCamTilt *= fac

	lastWallTilt = math.clamp(
		MathUtil.flerp(lastWallTilt, effCamTilt, TILT_DT), -WALL_TILT, WALL_TILT
	)
end

--------------------------------------------------------------------------------------------------
-- FPCam RenderStepped update
--------------------------------------------------------------------------------------------------

function FPCam:update(dt)
	if (self.switchToDeathCam) then
		return self:updateDeathCam(dt)
	end

	--self.resetCameraAngle = true
	local now = tick()
	local cam = Workspace.CurrentCamera
	local newCamCFrame = cam.CFrame
	local newCamFocus = cam.Focus

	if (self.lastUpdate == nil or dt > 1) then
		self.lastCameraTransform = nil
	end

	local subjCFrame: CFrame = self:getSubjectCFrame()
    --local subjVel: Vector3 = self:getSubjectVelocity()

    -- get rotation input
    local rotateInput = CamInput.getRotation(dt)
    if (rotateInput.Magnitude > 1) then
        rotateInput = rotateInput.Unit
    end

	-- reset Cam on respawn
	if (self.resetCameraAngle) then
		local rootPart: BasePart = self:getRootPart()
		camAngVec = VEC3_ZERO
		if (rootPart) then
			camAngVec = Vector3.new(0, rootPart.Orientation.Y, 0)
		end
		lastInpTilt = 0
		lastWallTilt = 0

		self.resetCameraAngle = false
	end

    -- calculate camera CFrame
	if (subjCFrame) then
        local adjInputVec = rotateInput * INP_SENS_FAC
        local x = (camAngVec.X - adjInputVec.Y)

        local rot_x = (x >= ROT_MAX_Y and ROT_MAX_Y) or (x <= ROT_MIN_Y and ROT_MIN_Y) or x
        local rot_y = (camAngVec.Y - adjInputVec.X) % 360

		-- Update effect cams
		self:updateDashCam(dt)
		self:updateWallCam(dt)

		-- Mouse movement linked camera tilting
		local limitedRotInp = math.clamp(rotateInput.X * 45, -INP_TILT, INP_TILT)
		lastInpTilt = MathUtil.flerp(lastInpTilt, limitedRotInp, TILT_DT)
		local rot_z = lastInpTilt + lastWallTilt

        camAngVec = Vector3.new(rot_x, rot_y, rot_z)
        newCamCFrame = CFrame.new(newCamFocus.Position + (ROOT_OFFSET + lastCamOffs))
            * CFrame.fromEulerAnglesXYZ(0, math.rad(camAngVec.Y), 0)
            * CFrame.fromEulerAnglesXYZ(math.rad(camAngVec.X), 0, 0)
            * CFrame.fromEulerAnglesXYZ(0, 0, math.rad(-camAngVec.Z))

        newCamFocus = CFrame.new(subjCFrame.Position)

		self.lastCameraTransform = newCamCFrame
		self.lastCameraFocus = newCamFocus
		--self.lastSubjectCFrame = nil
	end

	self.lastUpdate = now
	return self.lastCameraTransform, self.lastCameraFocus
end

return FPCam
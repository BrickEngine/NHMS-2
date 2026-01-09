-- Default first person camera

local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CamInput = require(script.Parent.CamInput)
local BaseCam = require(script.Parent.BaseCam)
local GameClient = require(ReplicatedStorage.Shared.GameClient)
local MathUtil = require(ReplicatedStorage.Shared.MathUtil)

--local INITIAL_CAM_ANG = CFrame.fromOrientation(math.rad(-15), 0, 0)
local ROOT_OFFSET = Vector3.new(0, 2.5, 0)
local DASH_OFFSET = Vector3.new(0, -1.8, 0)
local INP_SENS_FAC = 34	-- input sensitivity factor
local TILT_ANG = 6 -- max cam tilt angle in deg
local TILT_DT = 0.2	-- constant time delta for camera tilt lerp
local ROT_MIN_Y = -89 -- deg
local ROT_MAX_Y = 89 -- deg

local VEC3_ZERO = Vector3.zero

--------------------------------------------------------------------------------------------------
-- Module
--------------------------------------------------------------------------------------------------

local FPCam = setmetatable({}, BaseCam)
FPCam.__index = FPCam

function FPCam.new()
	local self = setmetatable(BaseCam.new(), FPCam)

	self.lastUpdate = tick()

	return self
end

--------------------------------------------------------------------------------------------------
-- FPCam RenderStepped update
--------------------------------------------------------------------------------------------------
local camAngVec = VEC3_ZERO
local lastCamOffs = VEC3_ZERO
local lastRotInp = 0

function FPCam:update(dt)
	self.resetCameraAngle = true
	local now = tick()
	local cam = Workspace.CurrentCamera
	local newCamCFrame = cam.CFrame
	local newCamFocus = cam.Focus

	-- local overrideCameraLookVector
	-- if self.resetCameraAngle then
	-- 	local rootPart: BasePart = self:getRootPart()
	-- 	if rootPart then
	-- 		overrideCameraLookVector = (rootPart.CFrame * INITIAL_CAM_ANG).LookVector
	-- 	else
	-- 		overrideCameraLookVector = INITIAL_CAM_ANG.LookVector
	-- 	end
	-- 	self.resetCameraAngle = false
	-- end

	local player = PlayersService.LocalPlayer

	if (self.lastUpdate == nil or dt > 1) then
		self.lastCameraTransform = nil
	end

	local subjCFrame: CFrame = self:getSubjectCFrame()
    --local subjVel: Vector3 = self:getSubjectVelocity()

    -- Get rotation input
    local rotateInput = CamInput.getRotation(dt)
    if (rotateInput.Magnitude > 1) then
        rotateInput = rotateInput.Unit
    end

    -- Calculate camera CFrame
	if (subjCFrame and player and cam) then
        local adjInputVec = rotateInput * INP_SENS_FAC
        local x = (camAngVec.X - adjInputVec.Y)

        local rot_x = (x >= ROT_MAX_Y and ROT_MAX_Y) or (x <= ROT_MIN_Y and ROT_MIN_Y) or x
        local rot_y = (camAngVec.Y - adjInputVec.X) % 360

		local effCamOffset = (GameClient:getIsDashing()) and DASH_OFFSET or VEC3_ZERO
		lastCamOffs = MathUtil.vec3Clamp(
			MathUtil.vec3Flerp(lastCamOffs, effCamOffset, dt * 20), DASH_OFFSET, VEC3_ZERO
		)
		-- local effCFOffset = lastCFCamOffs:Lerp(CFrame.new(effCamOffset), 0.05)
		-- lastCFCamOffs = effCFOffset

		-- Mouse movement linked camera tilting
		local limitedRotX = math.clamp(rotateInput.X * 45, -TILT_ANG, TILT_ANG)
		local rot_z = MathUtil.flerp(lastRotInp, limitedRotX, TILT_DT)
		lastRotInp = rot_z

        camAngVec = Vector3.new(rot_x, rot_y, rot_z)
        newCamCFrame = CFrame.new(newCamFocus.Position + (ROOT_OFFSET + lastCamOffs))
            * CFrame.fromEulerAnglesXYZ(0, math.rad(camAngVec.Y), 0)
            * CFrame.fromEulerAnglesXYZ(math.rad(camAngVec.X), 0, 0)
            * CFrame.fromEulerAnglesXYZ(0, 0, math.rad(-camAngVec.Z))
		
		-- local newLookVec = self:calculateNewLookVectorFromArg(overrideCameraLookVector, rotateInput)
		-- newCamCFrame = CFrame.lookAlong(newCamFocus.Position + CAM_OFFSET, newLookVec)

        newCamFocus = CFrame.new(subjCFrame.Position)

		self.lastCameraTransform = newCamCFrame
		self.lastCameraFocus = newCamFocus
		--self.lastSubjectCFrame = nil
	end

	self.lastUpdate = now
	return newCamCFrame, newCamFocus
end

return FPCam
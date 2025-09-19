-- Default first person camera

local PlayersService = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CamInput = require(script.Parent.CamInput)
local BaseCam = require(script.Parent.BaseCam)

local INITIAL_CAMERA_ANGLE = CFrame.fromOrientation(math.rad(-15), 0, 0)
local CAM_OFFSET = Vector3.new(0, 2.5, 0)
local CAM_SENS = 34
local BANK_DAMP = 0.05
local MIN_Y = -89
local MAX_Y = 89

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

local camAngVec = Vector3.zero

function FPCam:update(dt)
	local now = tick()
	local cam = Workspace.CurrentCamera
	local newCamCFrame = cam.CFrame
	local newCamFocus = cam.Focus

	local overrideCameraLookVector = nil
	if self.resetCameraAngle then
		local rootPart: BasePart = self:getRootPart()
		if rootPart then
			overrideCameraLookVector = (rootPart.CFrame * INITIAL_CAMERA_ANGLE).LookVector
		else
			overrideCameraLookVector = INITIAL_CAMERA_ANGLE.LookVector
		end
		self.resetCameraAngle = false
	end

	local player = PlayersService.LocalPlayer

	if (self.lastUpdate == nil or dt > 1) then
		self.lastCameraTransform = nil
	end

	local subjCFrame: CFrame = self:getSubjectCFrame()
    local subjVel: Vector3 = self:getSubjectVelocity()

    -- Get rotation input
    local rotateInput = CamInput.getRotation(dt)
    if (rotateInput.Magnitude > 1) then
        rotateInput = rotateInput.Unit
    end

    -- Calculate camera CFrame
	if (subjCFrame and player and cam) then
        local adjInputVec = rotateInput * CAM_SENS
        local x = (camAngVec.X - adjInputVec.Y)

        local rot_x = (x >= MAX_Y and MAX_Y) or (x <= MIN_Y and MIN_Y) or x
        local rot_y = (camAngVec.Y - adjInputVec.X) % 360

        local planeVelVec = Vector3.new(subjVel.X, 0, subjVel.Z)
        local rot_z = math.clamp(
            planeVelVec:Dot(subjCFrame.RightVector) * BANK_DAMP, -2.2, 2.2
        )
        camAngVec = Vector3.new(rot_x, rot_y, rot_z)

        newCamCFrame = CFrame.new(newCamFocus.Position + CAM_OFFSET)
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
-- Modified default Roblox 3rd person camera

local PlayersService = game:GetService("Players")

local CamInput = require(script.Parent.CamInput)
local BaseCam = require(script.Parent.BaseCam)

local INITIAL_CAMERA_ANGLE = CFrame.fromOrientation(math.rad(-15), 0, 0)
local SMOOTH_DELTA = 0.08

local ClassicCamera = setmetatable({}, BaseCam)
ClassicCamera.__index = ClassicCamera

function ClassicCamera.new()
	local self = setmetatable(BaseCam.new(), ClassicCamera)

	self.lastUpdate = tick()

	return self
end

-- Movement mode standardized to Enum.ComputerCameraMovementMode values
function ClassicCamera:setCameraMovementMode(cameraMovementMode: Enum.ComputerCameraMovementMode)
	BaseCam.setCameraMovementMode(self, cameraMovementMode)

	self.isFollowCamera = cameraMovementMode == Enum.ComputerCameraMovementMode.Follow
	self.isCameraToggle = cameraMovementMode == Enum.ComputerCameraMovementMode.CameraToggle
end

function ClassicCamera:update(dt)
	local now = tick()
	local camera = workspace.CurrentCamera
	local newCameraCFrame = camera.CFrame
	local newCameraFocus = camera.Focus

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
	local cameraSubject = camera.CameraSubject

	if self.lastUpdate == nil or dt > 1 then
		self.lastCameraTransform = nil
	end

	local rotateInput = CamInput.getRotation(dt)
	if (rotateInput.Magnitude > 1) then
		rotateInput = rotateInput.Unit
	end
	self:stepZoom()

	-- Reset tween speed if user is panning
	if rotateInput ~= Vector2.new() then
		self.lastUserPanCamera = tick()
	end

	local subjectPosition: Vector3 = self:getSubjectPosition()

	if subjectPosition and player and camera then
		local zoom = self:getCameraToSubjectDistance()

		if zoom < 0.5 then
			zoom = 0.5
		end

		newCameraFocus = CFrame.new(subjectPosition)
		local newLookVector = self:calculateNewLookVectorFromArg(overrideCameraLookVector, rotateInput)
		newCameraCFrame = CFrame.lookAlong(newCameraFocus.Position - (zoom * newLookVector), newLookVector)

		self.lastCameraTransform = newCameraCFrame
		self.lastCameraFocus = newCameraFocus
		self.lastSubjectCFrame = nil
	end

	self.lastUpdate = now
	return newCameraCFrame, newCameraFocus
end

return ClassicCamera
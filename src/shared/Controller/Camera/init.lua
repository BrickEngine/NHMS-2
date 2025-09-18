--[[
	CameraModule implements a singleton class to manage the
	selection, activation, and deactivation of the current camera controller, character occlusion controller.
	This script binds to RenderStepped at Camera priority and calls the Update() methods on the active controller instances.

	This is a modified version of the default Roblox Camera module with the following changes:
	- Dev camera mode settings are ignored (same behavior as Scriptable)
	- FPCam is the default and currently only camera controller
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local Workspace = game:GetService("Workspace")

local Global = require(ReplicatedStorage.Shared.Global)

local DEFAULT_FOV = 100

local DEBUG_CAM_SWITCH_KEY = Enum.KeyCode.P
local USE_OCCLUSION = false

local CAM_TYPES = {
	FPCam = "Default",
	ClassicCam = "Debug"
}

-- NOTICE: Player property names do not all match their StarterPlayer equivalents,
local PLAYER_CAMERA_PROPERTIES = {
	"DevEnableMouseLock",				-- Not used at the moment, mouse lock enabled by default
}

local USER_GAME_SETTINGS_PROPERTIES = {
	"ComputerCameraMovementMode",
	"ComputerMovementMode",
	"ControlMode",
	"GamepadCameraSensitivity",
	"MouseSensitivity",
	"RotationType"
}

local CamInput = require(script.CamInput)
local ClassicCam = require(script.ClassicCam)
local FPCam = require(script.FPCam)
local Occlusion = require(script.Occlusion)
local MouseLockController = require(script.MouseLockController)

local instantiatedCameraControllers = {}
local instantiatedOcclusionModules = {}

-- Management of which options appear on the Roblox User Settings screen
do
	local PlayerScripts = Players.LocalPlayer:WaitForChild("PlayerScripts")
	PlayerScripts:registerTouchCameraMovementMode(Enum.TouchCameraMovementMode.Default)
	PlayerScripts:registerComputerCameraMovementMode(Enum.ComputerCameraMovementMode.Default)
end

local CameraModule = {}
CameraModule.__index = CameraModule

function CameraModule.new()
	local self = setmetatable({},CameraModule)

	-- Current active controller instances
	self.activeCameraController = nil
	self.activeOcclusionModule = nil
	self.activeMouseLockController = nil
	self.debugCamSelected = false

	-- Connections to events
	self.cameraSubjectChangedConn = nil

	-- Add CharacterAdded and CharacterRemoving event handlers for all current players
	for _,player in pairs(Players:GetPlayers()) do
		self:onPlayerAdded(player)
	end

	-- Add CharacterAdded and CharacterRemoving event handlers for all players who join in the future
	Players.PlayerAdded:Connect(function(player)
		self:onPlayerAdded(player)
	end)

	-- Init mouse lock controller
	self.activeMouseLockController = MouseLockController.new()
	assert(self.activeMouseLockController, "Strict typing check")

	local toggleEvent = self.activeMouseLockController:getBindableToggleEvent()
	if toggleEvent then
		toggleEvent:Connect(function()
			self:onMouseLockToggled()
		end)
	end

	-- Switch to debug camera, if enabled
	if (Global.GAME_PHYS_DEBUG) then
		UserInputService.InputBegan:Connect(function(input, gpe)
			if (input.KeyCode == DEBUG_CAM_SWITCH_KEY and not gpe) then
				self.debugCamSelected = not self.debugCamSelected
				self:activateCameraController()
			end
		end)
	end

	self:activateCameraController()
	if (USE_OCCLUSION) then
		self:activateOcclusionModule()
	end

	self:onCurrentCameraChanged()
	RunService:BindToRenderStep("cameraRenderUpdate", Enum.RenderPriority.Camera.Value, function(dt) self:update(dt) end)

	-- Connect listeners to camera-related properties
	for _, propertyName in pairs(PLAYER_CAMERA_PROPERTIES) do
		Players.LocalPlayer:GetPropertyChangedSignal(propertyName):Connect(function()
			self:onLocalPlayerCameraPropertyChanged(propertyName)
		end)
	end

	-- for _, propertyName in pairs(USER_GAME_SETTINGS_PROPERTIES) do
	-- 	UserGameSettings:GetPropertyChangedSignal(propertyName):Connect(function()
	-- 		self:onUserGameSettingsPropertyChanged(propertyName)
	-- 	end)
	-- end

	game.Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:onCurrentCameraChanged()
	end)

	return self
end

-- function CameraModule:onUserGameSettingsPropertyChanged(propertyName: string)
-- 	if propertyName == "ComputerCameraMovementMode" then
-- 		self:activateCameraController()
-- 	end
-- end

function CameraModule:activateOcclusionModule()
	local newOccModule = Occlusion

	if self.activeOcclusionModule then
		if (not self.activeOcclusionModule:getEnabled()) then
			self.activeOcclusionModule:enable(true)
		end
		return
	end

	local prevOcclusionModule = self.activeOcclusionModule
	self.activeOcclusionModule = instantiatedOcclusionModules[newOccModule]

	if (not self.activeOcclusionModule) then
		self.activeOcclusionModule = newOccModule.new()
		instantiatedOcclusionModules[newOccModule] = self.activeOcclusionModule
	end

	if self.activeOcclusionModule then
		if (prevOcclusionModule) then
			if prevOcclusionModule ~= self.activeOcclusionModule then
				prevOcclusionModule:enable(false)
			else
				warn("CameraScript ActivateOcclusionModule failure to detect already running correct module")
			end
		end
        
        for _, player in pairs(Players:GetPlayers()) do
            if player and player.Character then
                self.activeOcclusionModule:characterAdded(player.Character, player)
            end
        end
        self.activeOcclusionModule:onCameraSubjectChanged((game.Workspace.CurrentCamera :: Camera).CameraSubject)
		self.activeOcclusionModule:enable(true)
	end
end

-- Activates the FPCam by default
function CameraModule:activateCameraController()
	local newCameraCreator = FPCam

	if (self.debugCamSelected) then
		newCameraCreator = ClassicCam
	end

	-- Create the camera control module we need if it does not already exist in instantiatedCameraControllers
	local newCameraController
	if not instantiatedCameraControllers[newCameraCreator] then
		newCameraController = newCameraCreator.new()
		instantiatedCameraControllers[newCameraCreator] = newCameraController
	else
		newCameraController = instantiatedCameraControllers[newCameraCreator]
		if newCameraController.Reset then
			newCameraController:reset()
		end
	end

	if self.activeCameraController then
		-- deactivate the old controller and activate the new one
		if self.activeCameraController ~= newCameraController then
			self.activeCameraController:enable(false)
			self.activeCameraController = newCameraController
			self.activeCameraController:enable(true)
		elseif not self.activeCameraController:getEnabled() then
			self.activeCameraController:enable(true)
		end
	elseif newCameraController ~= nil then
		-- only activate the new controller
		self.activeCameraController = newCameraController
		self.activeCameraController:enable(true)
	end
end

function CameraModule:onCameraSubjectChanged()
	local camera = workspace.CurrentCamera
	local cameraSubject = camera and camera.CameraSubject

	if self.activeOcclusionModule then
		self.activeOcclusionModule:onCameraSubjectChanged(cameraSubject)
	end

	self:activateCameraController()
end

-- Note: Called whenever workspace.CurrentCamera changes, but also on initialization of this script
function CameraModule:onCurrentCameraChanged()
	local currentCamera = game.Workspace.CurrentCamera
	if not currentCamera then return end

	if self.cameraSubjectChangedConn then
		self.cameraSubjectChangedConn:Disconnect()
	end

	self.cameraSubjectChangedConn = currentCamera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
		self:onCameraSubjectChanged()
	end)
	self:onCameraSubjectChanged()
end

function CameraModule:onLocalPlayerCameraPropertyChanged(propertyName: string)
	if propertyName == "CameraMinZoomDistance" or propertyName == "CameraMaxZoomDistance" then
		if self.activeCameraController then
			self.activeCameraController:updateForDistancePropertyChange()
		end
	end
end

--[[
	The camera modules should only return CFrames, not set the CFrame property of
	CurrentCamera directly.
--]]

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Main RenderStep update
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function CameraModule:update(dt: number)
	if self.activeCameraController then
		self.activeCameraController:updateMouseBehavior()

		local newCameraCFrame, newCameraFocus = self.activeCameraController:update(dt)

		if self.activeOcclusionModule then
			newCameraCFrame, newCameraFocus = self.activeOcclusionModule:update(dt, newCameraCFrame, newCameraFocus)
		end

		local currentCamera = game.Workspace.CurrentCamera :: Camera
		currentCamera.CFrame = newCameraCFrame
		currentCamera.Focus = newCameraFocus
		currentCamera.FieldOfView = DEFAULT_FOV

		if CamInput.getInputEnabled() then
			CamInput.resetInputForFrameEnd()
		end
	end
end

function CameraModule:onCharacterAdded(char: Model, player: Player)
	if self.activeOcclusionModule then
		self.activeOcclusionModule:characterAdded(char, player)
	end
	if (player == Players.LocalPlayer) then
		if (not char.PrimaryPart) then
			error("Character does not have a PrimaryPart assigned")
		end
		Workspace.CurrentCamera.CameraSubject = char
	end
end

function CameraModule:onCharacterRemoving(char: Model, player: Player)
	if self.activeOcclusionModule then
		self.activeOcclusionModule:characterRemoving(char, player)
	end
end

function CameraModule:onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(char: Model)
		self:onCharacterAdded(char, player)
	end)
	player.CharacterRemoving:Connect(function(char: Model)
		self:onCharacterRemoving(char, player)
	end)
end

function CameraModule:onMouseLockToggled()
	if self.activeMouseLockController then
		local mouseLocked = self.activeMouseLockController:getIsMouseLocked()
		if self.activeCameraController then
			self.activeCameraController:setIsMouseLocked(mouseLocked)
		end
	end
end

local cameraModuleObject = CameraModule.new()

return cameraModuleObject
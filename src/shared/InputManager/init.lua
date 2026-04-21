local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local typesFold = script.Types
local Keyboard = require(typesFold.Keyboard)
local Touch = require(typesFold.Touch)

local lastInpType

local ACTION_PRIO = 100
local NORMALIZE_INPUT = true
local VEC3_ZERO = Vector3.zero

local PC_INPUT_TYPE_MAP = table.freeze({
	[Enum.UserInputType.Keyboard] = Keyboard,
	[Enum.UserInputType.MouseButton1] = Keyboard,
	[Enum.UserInputType.MouseButton2] = Keyboard,
	[Enum.UserInputType.MouseButton3] = Keyboard,
	[Enum.UserInputType.MouseWheel] = Keyboard,
	[Enum.UserInputType.MouseMovement] = Keyboard,
})
local TOUCH_INPUT_TYPE_MAP = table.freeze({
    [Enum.UserInputType.Touch] = Touch
})

local InputManager = {}
InputManager.__index = InputManager

function InputManager.new()
    local self = setmetatable({}, InputManager)

    self.controlsEnabled = false

    self.inputControllers = {}
    
    self.activeInputController = nil

    self.touchControlArea = nil
    self.playerGui = nil
	self.touchGui = nil
	self.playerGuiAddedConn = nil

	UserInputService.LastInputTypeChanged:Connect(function(newLastInputType)
		self:onLastInputTypeChanged(newLastInputType)
	end)

	GuiService:GetPropertyChangedSignal("TouchControlsEnabled"):Connect(function()
		self:updateTouchGuiVisibility()
        self:updateActiveControlModuleEnabled()
	end)

	if (UserInputService.TouchEnabled) then
		self.playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if (self.playerGui) then
			self:createTouchGuiContainer()
			self:onLastInputTypeChanged(UserInputService:GetLastInputType())
		else
			self.playerGuiAddedConn = Players.LocalPlayer.ChildAdded:Connect(function(child)
				if child:IsA("PlayerGui") then
					self.playerGui = child
					self:createTouchGuiContainer()
					self.playerGuiAddedConn:Disconnect()
					self.playerGuiAddedConn = nil
					self:onLastInputTypeChanged(UserInputService:GetLastInputType())
				end
			end)
		end
	end

    return self
end

------------------------------------------------------------------------------------------------------------------------

function InputManager:setControlsEnabled(enable: boolean)
    self.controlsEnabled = enable
    self:updateActiveControlModuleEnabled()
end

function InputManager:getMoveVec(): Vector3
    if (not self.activeInputController) then
        return VEC3_ZERO
    end
    if (NORMALIZE_INPUT) then
        local vec: Vector3 = self.activeInputController:getMoveVec()
        if (vec.Magnitude > 1) then
            return vec.Unit
        else
            return vec
        end
    else
        return self.activeInputController:getMoveVec()
    end
end

function InputManager:getJumpKeyDown(): boolean
    if (not self.activeInputController) then
        return false
    end
    return self.activeInputController:getJumpKeyDown()
end

function InputManager:getDashKeyDown(): boolean
    if (not self.activeInputController) then
        return false
    end
    return self.activeInputController:getDashKeyDown()
end

function InputManager:getActiveInputController(): ({}?)
    return self.activeInputController
end

-- create container for all touch device guis
function InputManager:createTouchGuiContainer()
    if (self.touchGui) then self.touchGui:Destroy() end

	self.touchGui = Instance.new("ScreenGui")
	self.touchGui.Name = "TouchGui"
	self.touchGui.ResetOnSpawn = false
	self.touchGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	self:updateTouchGuiVisibility()
	self.touchGui.ClipToDeviceSafeArea = false;

	self.touchControlFrame = Instance.new("Frame")
	self.touchControlFrame.Name = "TouchControlFrame"
	self.touchControlFrame.Size = UDim2.new(1, 0, 1, 0)
	self.touchControlFrame.BackgroundTransparency = 1
	self.touchControlFrame.Parent = self.touchGui

	self.touchGui.Parent = self.playerGui
end

-- diables the current input controller, if inpModule is nil
function InputManager:switchInputController(inpModule: any)
    if (not inpModule) then
        if (self.activeInputController) then
            self.activeInputController:enable(false)
        end
        self.activeInputController = nil
        return
    end

    if (not self.inputControllers[inpModule]) then
        self.inputControllers[inpModule] = inpModule.new(ACTION_PRIO)
    end

    if (self.activeInputController ~= self.inputControllers[inpModule]) then
        if (self.activeInputController) then
            self.activeInputController:enable(false)
        end
        self.activeInputController = self.inputControllers[inpModule]
    end

    self:updateActiveControlModuleEnabled()
end

function InputManager:updateActiveControlModuleEnabled()
	-- helpers for disable/enable
	local disable = function()
		self.activeInputController:enable(false)
	end

	local enable = function()
        if (self.touchControlFrame) then
			self.activeInputController:enable(true, self.touchControlFrame)
		else
			self.activeInputController:enable(true)
		end
	end

	-- there is no active controller
	if (not self.activeInputController) then
		return
	end

	if (not self.controlsEnabled) then
		disable(); return
	end

	-- GuiService.TouchControlsEnabled == false and the active controller is a touch controller,
	-- disable controls
	if (not GuiService.TouchControlsEnabled
        and UserInputService.TouchEnabled
        and self.activeInputController == self.inputControllers[Touch]
    ) then
		disable(); return
	end

	-- No settings prevent enabling controls
	enable()
end

function InputManager:onLastInputTypeChanged(newlastInpType: Enum.UserInputType)
    if (lastInpType == newlastInpType) then
        warn("LastInputTypeChanged listener called with current input type")
    end

    lastInpType = newlastInpType

    if (TOUCH_INPUT_TYPE_MAP[lastInpType] ~= nil) then
        if (self.activeInputController and self.activeInputController == self.inputControllers[Touch]) then
            return
        end

        while not self.touchControlFrame do
            task.wait()
        end
        self:switchInputController(Touch)
        print("switching to touch controller")

    elseif (PC_INPUT_TYPE_MAP[lastInpType] ~= nil) then
        if (self.activeInputController and self.activeInputController == self.inputControllers[Keyboard]) then
            return
        end

        self:switchInputController(Keyboard)
        print("switching to keyboard controller")
    end
end

function InputManager:updateTouchGuiVisibility()
    if (self.touchGui) then
        self.touchGui.Enabled = GuiService.TouchControlsEnabled
    end
end

return InputManager.new()
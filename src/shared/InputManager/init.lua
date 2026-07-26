local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local typesFold = script.Types
local SlotSwitchType = require(script.SlotSwitchType)
local KeyboardMouse = require(typesFold.KeyboardMouse)
local Touch = require(typesFold.Touch)

local lastInpType

-- whether to allow switching input types in emulator mode
local DEBUG_SWITCH_INPTYPE = true

local ACTION_PRIO = 100
local NORMALIZE_INPUT = true
local VEC3_ZERO = Vector3.zero

local PC_INPUT_TYPE_MAP = table.freeze({
	[Enum.UserInputType.Keyboard] = KeyboardMouse,
	[Enum.UserInputType.MouseButton1] = KeyboardMouse,
	[Enum.UserInputType.MouseButton2] = KeyboardMouse,
	[Enum.UserInputType.MouseButton3] = KeyboardMouse,
	[Enum.UserInputType.MouseWheel] = KeyboardMouse,
	[Enum.UserInputType.MouseMovement] = KeyboardMouse,
})
local TOUCH_INPUT_TYPE_MAP = table.freeze({
    [Enum.UserInputType.Touch] = Touch
})

local InputManager = {}
InputManager.__index = InputManager

function InputManager.new()
    local self = setmetatable({}, InputManager)

    self.controlsEnabled = false
    self.voidInput = false

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

	if (UserInputService.TouchEnabled or DEBUG_SWITCH_INPTYPE) then
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

    -- if (DEBUG_ALLOW_SWITCH_INPTYPE) then
    --     warn("DEBUG - Manual input type switching enabled [Key: M]")

    --     local switchable = {Keyboard, Touch}
    --     local currIndex = 1

    --     local function switchToNextInpController(inpObj: InputObject, gameProcessed: boolean)
    --         if (gameProcessed or inpObj.KeyCode ~= Enum.KeyCode.M) then
    --             return
    --         end

    --         currIndex += 1
    --         if (currIndex > #switchable) then
    --             currIndex = 1
    --         end
    --         self:switchInputController(switchable[currIndex])
    --     end

    --     UserInputService.InputBegan:Connect(switchToNextInpController)
    -- end

    return self
end

------------------------------------------------------------------------------------------------------------------------

function InputManager:setControlsEnabled(enable: boolean)
    self.controlsEnabled = enable
    self:updateActiveControlModuleEnabled()
end

function InputManager:setVoidInput(voidInp: boolean)
    self.voidInput = voidInp
end

function InputManager:getMoveVec(): Vector3
    if (self.voidInput) then
        return VEC3_ZERO
    end
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
    if (self.voidInput) then
        return false
    end
    if (not self.activeInputController) then
        return false
    end
    return self.activeInputController:getJumpKeyDown()
end

function InputManager:getDashKeyDown(): boolean
    if (self.voidInput) then
        return false
    end
    if (not self.activeInputController) then
        return false
    end
    return self.activeInputController:getDashKeyDown()
end

function InputManager:getInteractKeyDown(): boolean
    if (self.voidInput) then
        return false
    end
    if (not self.activeInputController) then
        return false
    end
    return self.activeInputController:getInteractKeyDown()
end

--[[
    Returns whether 1) the fire key is down 2) the alt-fire key is down
    @return fire key down 
    @return alt-fire key down
]]
function InputManager:getFireKeysDown(): (boolean, boolean)
    if (self.voidInput) then
        return false, false
    end
    if (not self.activeInputController) then
        return false, false
    end
    return self.activeInputController:getFireKeysDown()
end

--[[ 
    Returns 1) whether a switch key is pressed 2) what type of switch occurs (enum)
    3) if the switch type is DIRECT (num keys), the corresponding number
    @return input
    @return switch type
    @return direct slot number
]]
function InputManager:getInvSwitchInput(currSlot: number): (boolean, string, number?)
    if (self.voidInput) then
        return false, SlotSwitchType.NONE, nil
    end
    if (not self.activeInputController) then
        return false, SlotSwitchType.NONE, nil
    end
    return self.activeInputController:getInvSwitchInput(currSlot)
end

------------------------------------------------------------------------------------------------------------------------

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

        while (not self.touchControlFrame) do
            task.wait()
        end
        self:switchInputController(Touch)
        print("switching to touch controller")

    elseif (PC_INPUT_TYPE_MAP[lastInpType] ~= nil) then
        if (self.activeInputController and self.activeInputController == self.inputControllers[KeyboardMouse]) then
            return
        end

        self:switchInputController(KeyboardMouse)
        print("switching to keyboard controller")
    end
end

function InputManager:updateTouchGuiVisibility()
    if (self.touchGui) then
        self.touchGui.Enabled = GuiService.TouchControlsEnabled
    end
end

return InputManager.new()
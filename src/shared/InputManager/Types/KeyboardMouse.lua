--[[
	Keyboard and mouse controls.
]]

local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local inpRootFold = script.Parent.Parent
local BaseInput = require(inpRootFold.Types.BaseInput)
local ContextActions = require(inpRootFold.ContextActions)
local SlotSwitchType = require(inpRootFold.SlotSwitchType)

local VEC3_ZERO = Vector3.zero
local KEY_W = Enum.KeyCode.W
local KEY_S = Enum.KeyCode.S
local KEY_A = Enum.KeyCode.A
local KEY_D = Enum.KeyCode.D
local KEY_DASH = Enum.KeyCode.LeftShift
local KEY_INTERACT = Enum.KeyCode.E
local KEY_JUMP = Enum.KeyCode.Space
local INPTYPE_FIRE = Enum.UserInputType.MouseButton1
local INPTYPE_ALT_FIRE = Enum.UserInputType.MouseButton2

-- inventory slots
local KEY_1 = Enum.KeyCode.One
local KEY_2 = Enum.KeyCode.Two
local KEY_3 = Enum.KeyCode.Three
local KEY_4 = Enum.KeyCode.Four
local KEY_5 = Enum.KeyCode.Five
local KEY_6 = Enum.KeyCode.Six
local KEY_7 = Enum.KeyCode.Seven
local KEY_8 = Enum.KeyCode.Eight
local KEY_9 = Enum.KeyCode.Nine
local KEY_0 = Enum.KeyCode.Zero
-- "next slot"
local KEY_F = Enum.KeyCode.F
-- select via mouse wheel
local INPTYPE_MOUSE_SCROLL = Enum.UserInputType.MouseWheel

local KEY_SLOT_MAP = {
	[KEY_1] = 1,
	[KEY_2] = 2,
	[KEY_3] = 3,
	[KEY_4] = 4,
	[KEY_5] = 5,
	[KEY_6] = 6,
	[KEY_7] = 7,
	[KEY_8] = 8,
	[KEY_9] = 9,
	[KEY_0] = 10
}

local KeyboardMouse = setmetatable({}, BaseInput)
KeyboardMouse.__index = KeyboardMouse

function KeyboardMouse.new(CONTROL_PRIORITY: number)
    local self = setmetatable(BaseInput.new() :: any, KeyboardMouse)

    self.CONTROL_PRIORITY = CONTROL_PRIORITY

    return self
end

function KeyboardMouse:enable(enable: boolean)
    if (enable == self.enabled) then
        return true
    end

    self.f_val, self.b_val, self.l_val, self.r_val = 0, 0, 0, 0
	self.jumpInp = false
	self.dashInp = false
	self.interInp = false
	self.fireInp = false
	self.altFireInp = false
	self.slotSwitchType = SlotSwitchType.NONE
	self.directSlot = 0
	self.scrollResetTask = nil

    self.moveVec = VEC3_ZERO
	self.isJumping = false
	self.isDashing = false
	self.isInteracting = false
	self.isFiring = false
	self.isAltFiring = false
	self.isSwitchingInvSlot = false

	if (enable) then
		self:bindActions()
		self:connectFocusEventListeners()
	else
		self._connectionUtil:disconnectAll()
	end

	self.enabled = enable
    return true
end

function KeyboardMouse:updateDash()
	self.isDashing = self.dashInp
end

function KeyboardMouse:updateJump()
	self.isJumping = self.jumpInp
end

function KeyboardMouse:updateInteract()
	self.isInteracting = self.interInp
end

function KeyboardMouse:updateMouse()
	self.isFiring = self.fireInp
	self.isAltFiring = self.altFireInp
end

function KeyboardMouse:updateInvSwitchInput(switchType: string, directSlot: number?)
	self.slotSwitchType = switchType
	self.isSwitchingInvSlot = switchType ~= SlotSwitchType.NONE
	self.directSlot = directSlot
end

function KeyboardMouse:getInvSwitchInput(): (boolean, string, number?)
    return self.isSwitchingInvSlot, self.slotSwitchType, self.directSlot
end

function KeyboardMouse:updateMoveVec(inputState: Enum.UserInputState)
    if (inputState == Enum.UserInputState.Cancel) then
        self.moveVec = VEC3_ZERO
    else
        self.moveVec = Vector3.new(self.l_val + self.r_val, 0, self.f_val + self.b_val)
    end
end

function KeyboardMouse:resetAllInputs()
	self.moveVector = VEC3_ZERO
	self.f_val, self.b_val, self.l_val, self.r_val = 0, 0, 0, 0
	self.jumpInp = false
	self.dashInp = false
	self.interInp = false
	self.fireInp = false
	self.altFireInp = false

	self:updateMoveVec()
	self:updateJump()
	self:updateDash()
	self:updateMouse()
	self:updateInteract()
end

function KeyboardMouse:bindActions()
	local handleMoveForward = function(_, inputState, inputObject)
		self.f_val = (inputState == Enum.UserInputState.Begin) and 1 or 0
		self:updateMoveVec(inputState)
		return Enum.ContextActionResult.Pass
	end
	local handleMoveBackward = function(_, inputState, inputObject)
		self.b_val = (inputState == Enum.UserInputState.Begin) and -1 or 0
		self:updateMoveVec(inputState)
		return Enum.ContextActionResult.Pass
	end
	local handleMoveLeft = function(_, inputState, inputObject)
		self.l_val = (inputState == Enum.UserInputState.Begin) and 1 or 0
		self:updateMoveVec(inputState)
		return Enum.ContextActionResult.Pass
	end
	local handleMoveRight = function(_, inputState, inputObject)
		self.r_val = (inputState == Enum.UserInputState.Begin) and -1 or 0
		self:updateMoveVec(inputState)
		return Enum.ContextActionResult.Pass
	end
	local handleJumpAction = function(_, inputState, inputObject)
		self.jumpInp = (inputState == Enum.UserInputState.Begin)
		self:updateJump()
		return Enum.ContextActionResult.Pass
	end
	local handleDashAction = function(_, inputState, inputObject)
		self.dashInp = (inputState == Enum.UserInputState.Begin)
		self:updateDash()
	end
	local handleInteractAction = function(_, inputState, inputObject)
		self.interInp = (inputState == Enum.UserInputState.Begin)
		self:updateInteract()
	end
	local handleFireAction = function(_, inputState, inputObject)
		self.fireInp = (inputState == Enum.UserInputState.Begin)
		self:updateMouse()
	end
	local handleAltFireAction = function(_, inputState, inputObject)
		self.altFireInp = (inputState == Enum.UserInputState.Begin)
		self:updateMouse()
	end
	local handleSlotSwitchInput = function(_, inputState: Enum.UserInputState, inputObject: InputObject)
		if (inputObject.UserInputType == INPTYPE_MOUSE_SCROLL and inputState == Enum.UserInputState.Change) then
			if (inputObject.Position.Z > 0) then
				self:updateInvSwitchInput(SlotSwitchType.NEXT)
			else
				self:updateInvSwitchInput(SlotSwitchType.PREV)
			end
			-- reset scrolling after short delay
			if (self.scrollResetTask) then
				task.cancel(self.scrollResetTask)
			end
			self.scrollResetTask = task.delay(0, function()
				self:updateInvSwitchInput(SlotSwitchType.NONE)
			end)
		elseif (inputObject.UserInputType == Enum.UserInputType.Keyboard and 
			inputObject.UserInputState == Enum.UserInputState.Begin) then
			local slotKey = KEY_SLOT_MAP[inputObject.KeyCode]
			if (slotKey) then
				self:updateInvSwitchInput(SlotSwitchType.DIRECT, slotKey)
			else 
				self:updateInvSwitchInput(SlotSwitchType.NEXT)
			end
		else
			self:updateInvSwitchInput(SlotSwitchType.NONE)
		end
	end

	ContextActionService:BindActionAtPriority(
		ContextActions.MOVE_F, handleMoveForward, false, self.CONTROL_PRIORITY, KEY_W)
	ContextActionService:BindActionAtPriority(
		ContextActions.MOVE_B, handleMoveBackward, false, self.CONTROL_PRIORITY, KEY_S)
	ContextActionService:BindActionAtPriority(
		ContextActions.MOVE_L, handleMoveLeft, false, self.CONTROL_PRIORITY, KEY_A)
	ContextActionService:BindActionAtPriority(
		ContextActions.MOVE_R, handleMoveRight, false, self.CONTROL_PRIORITY, KEY_D)
	ContextActionService:BindActionAtPriority(
		ContextActions.JUMP, handleJumpAction, false, self.CONTROL_PRIORITY, KEY_JUMP)
	ContextActionService:BindActionAtPriority(
		ContextActions.DASH, handleDashAction, false, self.CONTROL_PRIORITY, KEY_DASH)
	ContextActionService:BindActionAtPriority(
		ContextActions.INTERACT, handleInteractAction, false, self.CONTROL_PRIORITY, KEY_INTERACT)
	ContextActionService:BindActionAtPriority(
		ContextActions.FIRE, handleFireAction, false, self.CONTROL_PRIORITY, INPTYPE_FIRE)
	ContextActionService:BindActionAtPriority(
		ContextActions.ALT_FIRE, handleAltFireAction, false, self.CONTROL_PRIORITY, INPTYPE_ALT_FIRE)
	ContextActionService:BindActionAtPriority(
		ContextActions.SWITCH_INV_SLOT, handleSlotSwitchInput, false, self.CONTROL_PRIORITY,
		KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_F, INPTYPE_MOUSE_SCROLL)
	-- local wheelFwdConn = mouse.WheelForward:Connect()
	-- local wheelBwdConn = mouse.WheelBackward:Connect()

	self._connectionUtil:trackBoundFunction(
		ContextActions.MOVE_F, function() ContextActionService:UnbindAction(ContextActions.MOVE_F) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.MOVE_B, function() ContextActionService:UnbindAction(ContextActions.MOVE_B) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.MOVE_L, function() ContextActionService:UnbindAction(ContextActions.MOVE_L) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.MOVE_R, function() ContextActionService:UnbindAction(ContextActions.MOVE_R) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.JUMP, function() ContextActionService:UnbindAction(ContextActions.JUMP) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.DASH, function() ContextActionService:UnbindAction(ContextActions.DASH) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.INTERACT, function() ContextActionService:UnbindAction(ContextActions.INTERACT) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.FIRE, function() ContextActionService:UnbindAction(ContextActions.FIRE) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.ALT_FIRE, function() ContextActionService:UnbindAction(ContextActions.ALT_FIRE) end)
	self._connectionUtil:trackBoundFunction(
		ContextActions.SWITCH_INV_SLOT, 
		function() ContextActionService:UnbindAction(ContextActions.SWITCH_INV_SLOT) end)
	-- self._connectionUtil:trackBoundFunction(wheelFwdConn, function() wheelFwdConn:Disconnect() end)
	-- self._connectionUtil:trackBoundFunction(wheelBwdConn, function() wheelBwdConn:Disconnect() end)
end

function KeyboardMouse:connectFocusEventListeners()
	local function onFocusReleased()
		self.moveVector = VEC3_ZERO
		self.f_val, self.b_val, self.l_val, self.r_val = 0, 0, 0, 0
		self.jumpInp = false
		self.dashInp = false
		self.interInp = false
		self.fireInp = false
		self.altFireInp = false

		self:updateMoveVec()
		self:updateJump()
		self:updateDash()
		self:updateMouse()
		self:updateInteract()
	end

	local function onTextFocusGained(textboxFocused)
		self:resetAllInputs()
	end

	self._connectionUtil:trackConnection(
		"textBoxFocusReleased", UserInputService.TextBoxFocusReleased:Connect(onFocusReleased))
	self._connectionUtil:trackConnection(
		"textBoxFocused", UserInputService.TextBoxFocused:Connect(onTextFocusGained))
	self._connectionUtil:trackConnection(
		"windowFocusReleased", UserInputService.WindowFocused:Connect(onFocusReleased))
end

return KeyboardMouse
--!strict
--[[
    Abstract base class for character controller input.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SlotSwitchType = require(ReplicatedStorage.Shared.InputManager.SlotSwitchType)
local ConnectionUtil = require(ReplicatedStorage.Shared.Util.ConnectionUtil)

-- export type BaseInputType  = {
--     new: () -> BaseInputType,
--     getMoveVec: (BaseInputType) -> Vector3,
--     getIsJumping: (BaseInputType) -> boolean,
--     getIsDashing: (BaseInputType) -> boolean,
--     enable: (BaseInputType, enable: boolean) -> boolean,

--     _connectionUtil: any,

--     [string]: any
-- }

local VEC3_ZERO = Vector3.zero

local BaseInput = {}
BaseInput.__index = BaseInput

function BaseInput.new()
    local self = setmetatable({}, BaseInput) :: any

    self._connectionUtil = ConnectionUtil.new()

    self.enabled = false
    self.moveVec = VEC3_ZERO
	self.isJumping = false
	self.isDashing = false
	self.isInteracting = false
	self.isFiring = false
	self.isAltFiring = false
    self.isSwitchingInvSlot = false

    return self
end

function BaseInput:getMoveVec(): Vector3
    return self.moveVec
end

function BaseInput:getInvSwitchInput(): (boolean, string, number?)
    return self.isSwitchingInvSlot, SlotSwitchType.NONE, nil
end

function BaseInput:getJumpKeyDown(): boolean
    return self.isJumping
end

function BaseInput:getDashKeyDown(): boolean
    return self.isDashing
end

function BaseInput:getInteractKeyDown(): boolean
    return self.isInteracting
end

function BaseInput:getFireKeysDown(): (boolean, boolean)
    return self.isFiring, self.isAltFiring
end

function BaseInput:enable(enable: boolean): boolean
    error("cannot enable abstract class BaseMoveInput", 2)
end

return BaseInput
--!strict
-- Abstract base class for character controller input.

local ConnectionUtil = require(script.Parent.Common.ConnectionUtil)

export type BaseInputType  = {
    new: () -> BaseInputType,
    getMoveVec: (BaseInputType) -> Vector3,
    getIsJumping: (BaseInputType) -> boolean,
    getIsRunning: (BaseInputType) -> boolean,
    enable: (BaseInputType, enable: boolean) -> boolean,

    _connectionUtil: any,

    enabled: boolean,
    isJumping: boolean,
    isDashing: boolean,
    moveVec: Vector3,

    [string]: any
}

local VEC3_ZERO = Vector3.zero

local BaseMoveInput = {}
BaseMoveInput.__index = BaseMoveInput

function BaseMoveInput.new()
    local self = setmetatable({}, BaseMoveInput) :: BaseInputType

    self._connectionUtil = ConnectionUtil.new()

    self.enabled = false
    self.isJumping = false
    self.isDashing = false
    self.moveVec = VEC3_ZERO

    return self
end

function BaseMoveInput:getMoveVec(): Vector3
    return self.moveVec
end

function BaseMoveInput:getIsJumping(): boolean
    return self.isJumping
end

function BaseMoveInput:getIsDashing(): boolean
    return self.isDashing
end

function BaseMoveInput:enable(enable: boolean): boolean
    error("cannot enable abstract class BaseMoveInput", 2)
end

return BaseMoveInput
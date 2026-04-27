local Actions = table.freeze({
    -- movement
    MOVE_L = "MoveLeftAction",
    MOVE_R = "MoveRightAction",
    MOVE_F = "MoveForwardAction",
    MOVE_B = "MoveBackwardAction",
    MOVE_THUMBSTICK = "MoveThumbstickAction",
    -- actions pc
    JUMP = "JumpAction",
    DASH = "RunAction",
    INTERACT = "InteractAction",
    FIRE = "FireAction",
    ALT_FIRE = "AltFireAction",
    SWITCH_INV_SLOT = "SwitchInvSlotAction",
    -- actions mobile
    JUMP_BUTTON = "JumpButtonAction",
    DASH_BUTTON = "DashButtonAction",
    INTERACT_BUTTON = "InteractButtonAction",
    FIRE_BUTTON = "FireButtonAction",
    ALT_FIRE_BUTTON = "AltFireButtonAction",
    NEXT_SLOT_BUTTON = "NextWeaponButton",
    -- other
    MENU = "MenuOpenAction",
    MENU_BUTTON = "MenuButtonAction",
})

return Actions
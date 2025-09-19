local GLOBAL_VARS = {
    -- Debug
    GAME_PHYS_DEBUG = true,
    GAME_CHAR_DEBUG = false,
    GAME_UI_DEBUG = false,

    -- Reference Names
    PLAYERS_FOLD_NAME = "ActivePlayers",
    NET_FOLD_NAME = "Network"
}

table.freeze(GLOBAL_VARS)

return GLOBAL_VARS
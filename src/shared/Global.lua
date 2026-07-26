-- Global constants for client and server modules.

return table.freeze({
    GAME_PHYS_DEBUG = false,
    GAME_CHAR_DEBUG = true,
    GAME_UI_DEBUG = false,

    TAG_NAMES = {
        LAVA = "Lava",
        WALL = "Wall",
    },

    FOLDER_NAMES = {
        PLAYERS = "PlayerInstContainer",
        WALLS = "WallParts",
        LAVA = "LavaParts"
    },
})
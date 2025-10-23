-- systems/constants.lua
-- Central location for all hardcoded values in the game

local constants = {}

-- Display & Rendering
constants.RENDER_WIDTH = 960
constants.RENDER_HEIGHT = 540
constants.MIN_WINDOW_WIDTH = 640
constants.MIN_WINDOW_HEIGHT = 360

-- Input System
constants.INPUT = {
    GAMEPAD_DEADZONE = 0.15,
    STICK_THRESHOLD = 0.01,
    AIM_STICK_THRESHOLD = 0.1,

    -- Button repeat system
    REPEAT_DELAY = 0.3,
    REPEAT_INTERVAL = 0.1,
}

-- Vibration/Haptic Feedback (duration in seconds, strength 0.0-1.0)
constants.VIBRATION = {
    ATTACK = { duration = 0.1, left = 0.5, right = 0.5 },
    PARRY = { duration = 0.15, left = 0.8, right = 0.8 },
    PERFECT_PARRY = { duration = 0.3, left = 1.0, right = 1.0 },
    HIT = { duration = 0.2, left = 0.8, right = 0.3 },
    DODGE = { duration = 0.08, left = 0.4, right = 0.4 },
    WEAPON_HIT = { duration = 0.15, left = 0.7, right = 0.7 },
}

-- Player Stats
constants.PLAYER = {
    DEFAULT_SPEED = 300,
    DEFAULT_WIDTH = 50,
    DEFAULT_HEIGHT = 100,
    DEFAULT_X = 400,
    DEFAULT_Y = 200,
}

-- File Paths
constants.PATHS = {
    CRASH_LOG = "crash.log",
    CONFIG_FILE = "config.ini",
    IDENTITY = "hello_love2d",
}

-- Debug
constants.DEBUG = {
    BUTTON_SIZE = 60,
    SHOW_COLLIDERS = false,
    SHOW_FPS = true,
}

-- Virtual Gamepad (for mobile)
constants.VIRTUAL_GAMEPAD = {
    STICK_OUTER_RADIUS = 80,
    STICK_INNER_RADIUS = 30,
    BUTTON_RADIUS = 35,
    OPACITY = 0.5,
    STICK_DEADZONE = 0.2,
}

return constants

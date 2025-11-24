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
    DEFAULT_WIDTH = 40,
    DEFAULT_HEIGHT = 80,
    DEFAULT_X = 400,
    DEFAULT_Y = 200,
    JUMP_POWER = -600,

    -- Ground detection (platformer mode)
    RAYCAST_LENGTH = 1000,
    RAYCAST_LEFT_OFFSET = -5,
    RAYCAST_RIGHT_OFFSET = 5,
    GROUND_MARGIN = 5,
}

-- File Paths
constants.PATHS = {
    CRASH_LOG = "crash.log",
    CONFIG_FILE = "config.ini",
    IDENTITY = "hello_love2d",
}

-- Game Start Defaults (injected from game)
constants.GAME_START = {
    DEFAULT_MAP = nil,
    DEFAULT_SPAWN_X = nil,
    DEFAULT_SPAWN_Y = nil,
    DEFAULT_INTRO_ID = nil,
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

-- Healing Points
constants.HEALING_POINT = {
    DEFAULT_HEAL_AMOUNT = 50,
    DEFAULT_RADIUS = 40,
    DEFAULT_COOLDOWN = 5.0,
    PULSE_SPEED = 2,
    PARTICLE_MIN_SPEED = 20,
    PARTICLE_MAX_SPEED = 50,
}

-- Collision Classes (Box2D/Windfield)
constants.COLLISION_CLASSES = {
    PLAYER = "Player",
    PLAYER_DODGING = "PlayerDodging",
    PLAYER_FOOT = "PlayerFoot",  -- Topdown mode: foot collider for ground collision
    ENEMY = "Enemy",
    ENEMY_FOOT = "EnemyFoot",    -- Topdown mode: enemy foot collider for ground collision
    WALL = "Wall",
    WALL_BASE = "WallBase",      -- Topdown mode: base surface for player/enemy foot to collide with
    NPC = "NPC",
    WEAPON = "Weapon",
    HEALING_POINT = "HealingPoint",
    ITEM = "Item",
}

-- Combat System
constants.COMBAT = {
    -- Attack distance calculations
    VERTICAL_ATTACK_LIMIT = 50,  -- Max vertical distance for platformer attacks
    HUMANOID_WIDTH_RADIUS = 45,  -- Edge-to-edge distance for humanoid (horizontal/platformer)
    HUMANOID_HEIGHT_RADIUS = 90, -- Edge-to-edge distance for humanoid (vertical)
    SLIME_COLLIDER_WIDTH = 40,   -- Collider width for slime enemies
    DEFAULT_ATTACK_RANGE = 60,   -- Default enemy attack range

    -- Camera effects on parry
    PARRY_SHAKE_INTENSITY = 8,
    PARRY_SHAKE_DURATION = 0.2,
    PERFECT_PARRY_SLOW_MO = 0.3,    -- Slow-motion factor (0.3 = 30% speed)
    PERFECT_PARRY_SLOW_DURATION = 0.2,
    NORMAL_PARRY_SLOW_MO = 0.2,     -- Slow-motion factor (0.2 = 20% speed)
    NORMAL_PARRY_SLOW_DURATION = 0.4,
}

-- Enemy States
constants.ENEMY_STATES = {
    IDLE = "idle",
    PATROL = "patrol",
    CHASE = "chase",
    SEARCH = "search",  -- Lost sight, trying to find player by detouring around corners
    ATTACK_WINDUP = "attack_windup",
    ATTACK = "attack",
    HIT = "hit",
    DEAD = "dead",
}

return constants

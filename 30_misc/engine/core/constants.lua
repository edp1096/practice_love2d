-- systems/constants.lua
-- Central location for all hardcoded values in the game

local constants = {}

-- Display & Rendering
constants.RENDER_WIDTH = 960
constants.RENDER_HEIGHT = 540
constants.MIN_WINDOW_WIDTH = 640
constants.MIN_WINDOW_HEIGHT = 360

-- Camera & Minimap
constants.CAMERA = {
    ZOOM_FACTOR = 2.0,  -- In-game camera zoom (higher = more zoomed in)
}

constants.MINIMAP = {
    ZOOM_FACTOR = 1.2,  -- Minimap zoom level (1x = normal scale, higher = more detail/smaller area)
    LIGHTING_BRIGHTNESS = 0.2,  -- How much to brighten lighting for minimap visibility (0 = full dark, 1 = no lighting)
}

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

-- UI Layout Constants
constants.UI = {
    PADDING_SMALL = 5,
    PADDING_MEDIUM = 10,
    PADDING_LARGE = 20,
    SPACING_SMALL = 5,
    SPACING_MEDIUM = 10,
    SPACING_LARGE = 15,
    PANEL_MARGIN = 20,
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

-- Collider Offset Constants (for dual collider system)
-- These define foot collider proportions relative to entity height
constants.COLLIDER_OFFSETS = {
    -- Player foot collider (topdown mode)
    PLAYER_FOOT_HEIGHT = 0.2465,      -- 24.65% of collider height
    PLAYER_FOOT_POSITION = 0.40625,   -- Position at 81.25% down from center

    -- Humanoid enemy foot collider (human-shaped enemies)
    HUMANOID_FOOT_HEIGHT = 0.125,     -- 12.5% of collider height (bottom portion)
    HUMANOID_FOOT_POSITION = 0.4375,  -- Position at 87.5% down from center

    -- Slime enemy foot collider (blob-shaped enemies)
    SLIME_FOOT_HEIGHT = 0.6,          -- 60% of collider height (large bottom)
    SLIME_FOOT_POSITION = 0.2,        -- Position at 40% down from center

    -- NPC foot collider
    NPC_FOOT_HEIGHT = 0.25,           -- 25% of collider height
    NPC_FOOT_POSITION = 0.75,         -- Start at 75% down (bottom 25%)

    -- Vehicle foot collider
    VEHICLE_FOOT_HEIGHT = 0.3,          -- 30% of collider height
    VEHICLE_FOOT_POSITION = 0.35,       -- Position at 70% down from center

    -- Rendering/Sorting offsets
    PLAYER_SORT_HEIGHT = 0.26,        -- For Y-sort calculation
}

-- Collision Classes (Box2D/Windfield)
constants.COLLISION_CLASSES = {
    PLAYER = "Player",
    PLAYER_DODGING = "PlayerDodging",
    PLAYER_FOOT = "PlayerFoot",  -- Topdown mode: foot collider for ground collision
    PLAYER_FOOT_DODGING = "PlayerFootDodging",  -- Topdown mode: foot collider during dodge (passes through enemies)
    ENEMY = "Enemy",
    ENEMY_FOOT = "EnemyFoot",    -- Topdown mode: enemy foot collider for ground collision
    WALL = "Wall",
    WALL_BASE = "WallBase",      -- Topdown mode: base surface for player/enemy foot to collide with
    NPC = "NPC",
    NPC_FOOT = "NPCFoot",        -- Topdown mode: NPC foot collider for ground collision
    PROP = "Prop",               -- Prop entity (movable/breakable objects)
    PROP_FOOT = "PropFoot",      -- Topdown mode: prop foot collider for ground collision
    VEHICLE = "Vehicle",         -- Vehicle entity (rideable: horse, boat, etc.)
    VEHICLE_FOOT = "VehicleFoot", -- Topdown mode: vehicle foot collider for ground collision
    HEALING_POINT = "HealingPoint",
    ITEM = "Item",
}

-- Combat System
constants.COMBAT = {
    -- Attack distance calculations
    VERTICAL_ATTACK_LIMIT = 50,  -- Max vertical distance for platformer attacks
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

-- Shadow Rendering (shared across player, enemy, vehicle)
constants.SHADOW = {
    -- Common ratios
    WIDTH_RATIO = 0.625,       -- shadow_width = collider_width * 0.625
    HEIGHT_RATIO = 0.175,      -- shadow_height = collider_width * 0.175
    ALPHA = 0.4,               -- Default shadow transparency
    MIN_SCALE = 0.3,           -- Minimum shadow scale during jump
    MIN_ALPHA = 0.1,           -- Minimum shadow alpha during jump

    -- Topdown jump scaling
    TOPDOWN_SCALE_DIVISOR = 100,   -- shadow_scale = 1.0 - (height / 100)
    TOPDOWN_ALPHA_DIVISOR = 125,   -- shadow_alpha = 0.4 - (height / 125)

    -- Platformer scaling
    PLATFORMER_SCALE_DIVISOR = 300,  -- shadow_scale = 1.0 - (height / 300)
    PLATFORMER_ALPHA_DIVISOR = 500,  -- shadow_alpha = 0.4 - (height / 500)

    -- Vehicle-specific (colorbox fallback)
    VEHICLE_COLORBOX_WIDTH_RATIO = 0.4,
    VEHICLE_COLORBOX_HEIGHT_RATIO = 0.2,

    -- Vehicle sprite
    VEHICLE_SPRITE_WIDTH_RATIO = 0.3,
    VEHICLE_SPRITE_HEIGHT_RATIO = 0.15,
}

-- Hit Flash Effect
constants.HIT_FLASH = {
    DURATION = 0.15,           -- Enemy hit flash duration
    PLAYER_DURATION = 0.2,     -- Player hit flash duration
    INTENSITY = 0.7,           -- Flash intensity multiplier
}

-- Parry Visual Effects
constants.PARRY_VISUAL = {
    SHIELD_PULSE_SPEED = 10,   -- Shield alpha oscillation speed
    SHIELD_ALPHA_MIN = 0.3,
    SHIELD_ALPHA_RANGE = 0.2,
    SHIELD_RADIUS_RATIO = 0.8, -- shield_radius = collider_width * 0.8
}

-- Invincibility Blink
constants.BLINK = {
    INTERVAL = 0.1,            -- Blink cycle duration
}

return constants

-- game/data/entities/vehicles.lua
-- Vehicle type definitions
-- Engine uses this data via dependency injection

local vehicles = {}

-- Ride effect types:
--   "animated" = play rider animation frames (horse, bicycle, kickboard)
--   "vibration" = fixed frame with micro-vibration when moving (scooter)

-- Horse - fast land movement
vehicles.horse = {
    name = "Horse",
    ride_speed = 230,           -- Speed when boarded (default player: 260)
    interaction_range = 60,     -- Range to interact with vehicle

    -- Color box rendering (prototype - no sprites yet)
    color = {0.6, 0.4, 0.2, 1}, -- Brown
    width = 64,                 -- Visual width
    height = 40,                -- Visual height

    -- Collider dimensions
    collider_width = 48,
    collider_height = 32,

    -- Ride effect
    ride_effect = "animated",   -- Play ride animation frames

    -- Custom sounds (optional - uses defaults if not specified)
    -- sounds = {
    --     summon = "assets/sound/vehicle/horse_neigh.wav",
    --     board = "assets/sound/vehicle/horse_mount.wav",
    --     dismount = "assets/sound/vehicle/horse_dismount.wav",
    --     engine_loop = "assets/sound/vehicle/horse_gallop.wav",
    -- },
}

-- Donkey - slower but more stable
vehicles.donkey = {
    name = "Donkey",
    ride_speed = 220,
    interaction_range = 60,

    color = {0.5, 0.5, 0.5, 1}, -- Gray
    width = 56,
    height = 36,

    collider_width = 40,
    collider_height = 28,

    ride_effect = "animated",
}

-- Bicycle - pedaling animation
vehicles.bicycle = {
    name = "Bicycle",
    ride_speed = 200,
    interaction_range = 50,

    color = {0.2, 0.2, 0.8, 1}, -- Blue
    width = 48,
    height = 32,

    collider_width = 32,
    collider_height = 24,

    ride_effect = "animated",   -- Pedaling animation
}

-- Kickboard - kick animation
vehicles.kickboard = {
    name = "Kickboard",
    ride_speed = 220,
    interaction_range = 40,

    color = {0.8, 0.2, 0.2, 1}, -- Red
    width = 40,
    height = 24,

    collider_width = 28,
    collider_height = 20,

    ride_effect = "animated",   -- Kick animation
}

-- Scooter base config (shared properties)
-- Sprite: 72x48, no padding, full coverage
local scooter_base = {
    ride_speed = 300,
    interaction_range = 50,
    width = 72,
    height = 48,
    collider_width = 72,   -- Same as sprite (no padding)
    collider_height = 48,  -- Same as sprite (no padding)
    ride_effect = "vibration",
    vibration_intensity = 0.5,
    vibration_speed_idle = 60,
    vibration_speed_move = 120,
}

-- Scooter 1 (cyan/teal)
vehicles.scooter1 = {
    name = "Scooter",
    ride_speed = scooter_base.ride_speed,
    interaction_range = scooter_base.interaction_range,

    sprite = {
        sheet = "assets/images/sprites/vehicles/scooter1.png",
        frame_width = 72,
        frame_height = 48,
        scale = 1,
        frames = { down = 1, left = 2, right = 3, up = 4 },
    },

    color = {0.3, 0.8, 0.8, 1}, -- Cyan (fallback)
    width = scooter_base.width,
    height = scooter_base.height,
    collider_width = scooter_base.collider_width,
    collider_height = scooter_base.collider_height,

    ride_effect = scooter_base.ride_effect,
    vibration_intensity = scooter_base.vibration_intensity,
    vibration_speed_idle = scooter_base.vibration_speed_idle,
    vibration_speed_move = scooter_base.vibration_speed_move,

    -- Custom sounds for scooter (engine sounds)
    -- sounds = {
    --     summon = "assets/sound/vehicle/scooter_start.wav",
    --     board = "assets/sound/vehicle/scooter_board.wav",
    --     dismount = "assets/sound/vehicle/scooter_off.wav",
    --     engine_loop = "assets/sound/vehicle/scooter_engine.wav",
    -- },
}

-- Scooter 2 (dark/black)
vehicles.scooter2 = {
    name = "Scooter",
    ride_speed = scooter_base.ride_speed,
    interaction_range = scooter_base.interaction_range,

    sprite = {
        sheet = "assets/images/sprites/vehicles/scooter2.png",
        frame_width = 72,
        frame_height = 48,
        scale = 1,
        frames = { down = 1, left = 2, right = 3, up = 4 },
    },

    color = {0.2, 0.2, 0.2, 1}, -- Dark gray (fallback)
    width = scooter_base.width,
    height = scooter_base.height,
    collider_width = scooter_base.collider_width,
    collider_height = scooter_base.collider_height,

    ride_effect = scooter_base.ride_effect,
    vibration_intensity = scooter_base.vibration_intensity,
    vibration_speed_idle = scooter_base.vibration_speed_idle,
    vibration_speed_move = scooter_base.vibration_speed_move,
}

-- Boat - water travel (for future use)
vehicles.boat = {
    name = "Boat",
    ride_speed = 300,
    interaction_range = 80,

    color = {0.4, 0.3, 0.2, 1}, -- Dark wood
    width = 80,
    height = 48,

    collider_width = 64,
    collider_height = 40,

    ride_effect = "animated",
    water_only = true,          -- Can only be used on water
}

-- ===========================================
-- Vehicle System Settings (per-game configuration)
-- ===========================================
vehicles.settings = {
    -- Enable/disable vehicle summoning feature
    -- Set to false for games where vehicles are map-fixed only
    allow_summon = true,

    -- Cooldown between summons (seconds)
    summon_cooldown = 3,

    -- Only allow one summoned vehicle at a time
    one_summon_only = true,

    -- Auto-dismiss summoned vehicle when entering indoor maps (allow_vehicle=false)
    -- If false, vehicle stays at last outdoor position
    auto_dismiss_on_indoor = false,

    -- Summon cost (gold) - 0 for free
    summon_cost = 0,
}

return vehicles

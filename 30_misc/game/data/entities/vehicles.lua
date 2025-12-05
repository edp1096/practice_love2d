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
    ride_speed = 500,           -- Speed when boarded (default player: 260)
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
}

-- Donkey - slower but more stable
vehicles.donkey = {
    name = "Donkey",
    ride_speed = 350,
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
    ride_speed = 400,
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
    ride_speed = 320,
    interaction_range = 40,

    color = {0.8, 0.2, 0.2, 1}, -- Red
    width = 40,
    height = 24,

    collider_width = 28,
    collider_height = 20,

    ride_effect = "animated",   -- Kick animation
}

-- Scooter - vibration effect
vehicles.scooter = {
    name = "Scooter",
    ride_speed = 450,
    interaction_range = 50,

    color = {0.5, 0.15, 0.15, 1}, -- Maroon (적갈색)
    width = 52,
    height = 32,

    collider_width = 36,
    collider_height = 24,

    ride_effect = "vibration",  -- Fixed frame + micro-vibration
    vibration_intensity = 0.5,  -- Pixels of vibration (subtle engine vibration)
    vibration_speed_idle = 60,  -- Idle RPM vibration frequency
    vibration_speed_move = 120, -- Moving RPM vibration frequency (higher)
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

return vehicles

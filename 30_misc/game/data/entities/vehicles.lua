-- game/data/entities/vehicles.lua
-- Vehicle type definitions
-- Engine uses this data via dependency injection

local vehicles = {}

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

    -- Special properties
    water_only = true,          -- Can only be used on water
}

return vehicles

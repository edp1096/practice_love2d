-- game/data/start.lua
-- Game start configuration (starting map, spawn points, etc.)

local start_config = {}

-- Game Start Defaults
start_config.map = "assets/maps/level1/area1.lua"
start_config.spawn_x = 120
start_config.spawn_y = 130
start_config.intro_id = "level1"

-- Starting Inventory Items
start_config.starting_items = {
    {type = "small_potion", quantity = 3},
    {type = "large_potion", quantity = 1}
}

return start_config

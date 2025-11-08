-- game/data/game_config.lua
-- Game-level configuration (starting map, spawn points, etc.)

local game_config = {}

-- Game Start Defaults
game_config.start = {
  map = "assets/maps/level1/area1.lua",
  spawn_x = 400,
  spawn_y = 250,
}

return game_config

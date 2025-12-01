-- scenes/gameover.lua (Data-driven version)

local builder = require "engine.scenes.builder"
local scene_configs = require "game.data.scenes"

return builder:build("gameover", scene_configs)

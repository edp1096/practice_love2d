-- engine/systems/hud/init.lua
-- HUD system module bundle

return {
    minimap = require "engine.systems.hud.minimap",
    status = require "engine.systems.hud.status",
    quest_tracker = require "engine.systems.hud.quest_tracker",
    vehicles = require "engine.systems.hud.vehicles",
}

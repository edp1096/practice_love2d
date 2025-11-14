-- engine/entities/weapon/config/init.lua
-- Weapon configuration module bundle

return {
    hand_anchors = require "engine.entities.weapon.config.hand_anchors",
    handle_anchors = require "engine.entities.weapon.config.handle_anchors",
    swing_configs = require "engine.entities.weapon.config.swing_configs",
}

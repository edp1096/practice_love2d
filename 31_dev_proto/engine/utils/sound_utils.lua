-- engine/utils/sound_utils.lua
-- Safe sound wrapper utility to avoid duplicate code across UI modules

local sound = require "engine.core.sound"

local sound_utils = {}

-- Play sound effect safely (with error handling)
-- @param category: sound category (e.g., "ui", "combat")
-- @param name: sound name (e.g., "move", "select", "error")
function sound_utils.play(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

-- Alias for backward compatibility
sound_utils.playSFX = sound_utils.play

return sound_utils

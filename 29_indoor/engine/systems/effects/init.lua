-- engine/effects/init.lua
-- Unified effects interface with backward compatibility
-- Provides access to particles and screen effects subsystems

local particles = require "engine.systems.effects.particles"
local screen = require "engine.systems.effects.screen"

local effects = {
    particles = particles,
    screen = screen
}

-- Backward compatibility: Forward all method calls to particles
-- This ensures existing code like effects:spawn() still works
setmetatable(effects, {
    __index = function(t, k)
        -- Forward method calls to particles subsystem
        return particles[k]
    end
})

return effects

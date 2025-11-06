-- engine/effects/particles/init.lua
-- Particle effect manager (active effects, update, draw)

local systems = require "engine.effects.particles.systems"
local presets = require "engine.effects.particles.presets"

local particles = {}

particles.active_effects = {}
particles.particle_systems = {}

-- Debug reference (set externally to avoid circular dependency)
particles.debug = nil

-- Initialize all particle systems
function particles:init()
    self.particle_systems = {
        blood = systems.createBloodSystem(),
        spark = systems.createSparkSystem(),
        dust = systems.createDustSystem(),
        slash = systems.createSlashSystem()
    }
    dprint("Particle effects system initialized")
end

-- Spawn an effect at a position
function particles:spawn(effect_type, x, y, angle, particle_count)
    if not self.particle_systems[effect_type] then
        print("WARNING: Unknown effect type: " .. tostring(effect_type))
        return
    end

    particle_count = particle_count or 30

    local ps = self.particle_systems[effect_type]:clone()
    ps:setPosition(0, 0)

    if angle then
        ps:setDirection(angle)
    end

    ps:emit(particle_count)

    table.insert(self.active_effects, {
        ps = ps,
        x = x,
        y = y,
        lifetime = 3.0,
        time = 0,
        type = effect_type
    })

    -- Debug logging (check if debug is available)
    if self.debug and self.debug.show_effects then
        dprint(string.format("Spawned %s effect at (%.1f, %.1f) with %d particles",
            effect_type, x, y, particle_count))
    end
end

-- Update all active effects
function particles:update(dt)
    for i = #self.active_effects, 1, -1 do
        local effect = self.active_effects[i]

        effect.time = effect.time + dt
        effect.ps:update(dt)

        if effect.time > effect.lifetime or effect.ps:getCount() == 0 then
            -- Debug logging
            if self.debug and self.debug.show_effects then
                dprint(string.format("Removing %s effect (time: %.2f, particles: %d)",
                    effect.type, effect.time, effect.ps:getCount()))
            end
            table.remove(self.active_effects, i)
        end
    end
end

-- Draw all active effects
function particles:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")

    for _, effect in ipairs(self.active_effects) do
        love.graphics.draw(effect.ps, effect.x, effect.y)

        -- Debug visualization
        if self.debug and self.debug.show_effects then
            love.graphics.setColor(1, 0, 1, 0.5)
            love.graphics.circle("line", effect.x, effect.y, 20)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Clear all effects
function particles:clear()
    if self.debug and self.debug.show_effects then
        dprint("Clearing " .. #self.active_effects .. " effects")
    end
    self.active_effects = {}
end

-- Get active effect count (for debugging)
function particles:getCount()
    return #self.active_effects
end

-- Attach preset methods
particles.spawnHitEffect = function(self, x, y, target_type, angle)
    presets.spawnHitEffect(self, x, y, target_type, angle)
end

particles.spawnParryEffect = function(self, x, y, angle, is_perfect)
    presets.spawnParryEffect(self, x, y, angle, is_perfect)
end

particles.spawnWeaponTrail = function(self, x, y, angle)
    presets.spawnWeaponTrail(self, x, y, angle)
end

particles.test = function(self, x, y)
    presets.test(self, x, y)
end

-- Initialize on require
particles:init()

return particles

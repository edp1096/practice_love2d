-- systems/effects.lua
-- Central effect management system with debugging

local effects = {}

effects.active_effects = {}
effects.particle_systems = {}
effects.debug_mode = false

-- Create particle image (larger for visibility)
local function createParticleImage(size)
    local particle_data = love.image.newImageData(size, size)
    particle_data:mapPixel(function(x, y, r, g, b, a)
        local dx = x - size / 2
        local dy = y - size / 2
        local dist = math.sqrt(dx * dx + dy * dy)
        local alpha = math.max(0, 1 - dist / (size / 2))
        return 1, 1, 1, alpha
    end)
    return love.graphics.newImage(particle_data)
end

-- Blood effect (red particles, splash outward)
function effects:createBloodSystem()
    local particle_img = createParticleImage(12)                 -- Larger
    local ps = love.graphics.newParticleSystem(particle_img, 60) -- More particles

    ps:setParticleLifetime(0.5, 1.0)                             -- Longer lifetime
    ps:setEmissionRate(0)
    ps:setSizes(2, 3, 2, 1, 0)                                   -- Larger sizes

    -- Brighter red blood colors
    ps:setColors(
        1, 0.1, 0.1, 1,   -- Bright red
        0.9, 0.0, 0.0, 1, -- Red
        0.7, 0.0, 0.0, 0.8,
        0.5, 0.0, 0.0, 0.5,
        0.3, 0.0, 0.0, 0 -- Fade out
    )

    ps:setLinearDamping(1, 3) -- Slower damping
    ps:setSpeed(100, 180)     -- Faster
    ps:setSpread(math.pi * 2)
    ps:setRotation(0, math.pi * 2)

    return ps
end

-- Spark effect (yellow/white, metal clash)
function effects:createSparkSystem()
    local particle_img = createParticleImage(10)                 -- Larger
    local ps = love.graphics.newParticleSystem(particle_img, 50) -- More particles

    ps:setParticleLifetime(0.3, 0.6)                             -- Longer
    ps:setEmissionRate(0)
    ps:setSizes(2.5, 3, 2, 1, 0)                                 -- Larger

    -- Brighter yellow/white sparks
    ps:setColors(
        1, 1, 1, 1,       -- Bright white
        1, 1, 0.6, 1,     -- Yellow
        1, 0.9, 0.3, 0.9, -- Orange-yellow
        0.9, 0.6, 0.1, 0.5,
        0.6, 0.4, 0, 0    -- Fade out
    )

    ps:setLinearDamping(2, 5)
    ps:setSpeed(120, 250) -- Faster
    ps:setSpread(math.pi / 3)
    ps:setRotation(0, math.pi * 2)

    return ps
end

-- Dust effect (gray/brown, impact on ground)
function effects:createDustSystem()
    local particle_img = createParticleImage(14) -- Larger
    local ps = love.graphics.newParticleSystem(particle_img, 50)

    ps:setParticleLifetime(0.6, 1.2) -- Longer
    ps:setEmissionRate(0)
    ps:setSizes(3, 4, 5, 3, 0)       -- Larger

    -- Lighter dust colors
    ps:setColors(
        0.7, 0.6, 0.5, 0.9, -- Light brown
        0.6, 0.5, 0.4, 0.7, -- Medium brown
        0.5, 0.4, 0.3, 0.5, -- Darker
        0.4, 0.3, 0.2, 0.3,
        0.3, 0.2, 0.1, 0    -- Fade out
    )

    ps:setLinearDamping(0.5, 2)
    ps:setSpeed(60, 140)
    ps:setSpread(math.pi)
    ps:setRotation(0, math.pi * 2)

    return ps
end

-- Slash trail effect (cyan/white, sword trail)
function effects:createSlashSystem()
    local particle_img = createParticleImage(12) -- Larger
    local ps = love.graphics.newParticleSystem(particle_img, 50)

    ps:setParticleLifetime(0.2, 0.4) -- Longer
    ps:setEmissionRate(0)
    ps:setSizes(2.5, 3, 2.5, 1, 0)   -- Larger

    -- Brighter cyan/white slash trail
    ps:setColors(
        1, 1, 1, 1,       -- Bright white
        0.6, 1, 1, 1,     -- Bright cyan
        0.4, 0.8, 1, 0.8, -- Cyan
        0.3, 0.6, 0.9, 0.4,
        0.2, 0.4, 0.7, 0  -- Fade out
    )

    ps:setLinearDamping(1, 3)
    ps:setSpeed(80, 120)
    ps:setSpread(math.pi / 4)
    ps:setRotation(0, math.pi * 2)

    return ps
end

-- Initialize all particle systems
function effects:init()
    self.particle_systems = {
        blood = self:createBloodSystem(),
        spark = self:createSparkSystem(),
        dust = self:createDustSystem(),
        slash = self:createSlashSystem()
    }
    print("Effects system initialized with " .. #self.active_effects .. " active effects")
end

-- Spawn an effect at a position
function effects:spawn(effect_type, x, y, angle, particle_count)
    if not self.particle_systems[effect_type] then
        print("WARNING: Unknown effect type: " .. tostring(effect_type))
        return
    end

    particle_count = particle_count or 30 -- More particles by default

    -- Clone particle system for this instance
    local ps = self.particle_systems[effect_type]:clone()

    -- Set position to 0,0 (relative coordinates)
    -- We'll pass the actual position in draw()
    ps:setPosition(0, 0)

    -- Set direction if angle provided
    if angle then
        ps:setDirection(angle)
    end

    -- Emit particles
    ps:emit(particle_count)

    -- Add to active effects
    table.insert(self.active_effects, {
        ps = ps,
        x = x,
        y = y,
        lifetime = 3.0, -- Longer lifetime
        time = 0,
        type = effect_type
    })

    if self.debug_mode then
        print(string.format("Spawned %s effect at (%.1f, %.1f) with %d particles",
            effect_type, x, y, particle_count))
    end
end

-- Spawn directional effect (for weapon hits)
function effects:spawnDirectional(effect_type, x, y, direction_x, direction_y, particle_count)
    local angle = math.atan2(direction_y, direction_x)
    self:spawn(effect_type, x, y, angle, particle_count)
end

-- Update all active effects
function effects:update(dt)
    for i = #self.active_effects, 1, -1 do
        local effect = self.active_effects[i]

        effect.time = effect.time + dt
        effect.ps:update(dt)

        -- Remove if expired or no particles
        if effect.time > effect.lifetime or effect.ps:getCount() == 0 then
            if self.debug_mode then
                print(string.format("Removing %s effect (time: %.2f, particles: %d)",
                    effect.type, effect.time, effect.ps:getCount()))
            end
            table.remove(self.active_effects, i)
        end
    end
end

-- Draw all active effects
function effects:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")

    for _, effect in ipairs(self.active_effects) do
        love.graphics.draw(effect.ps, effect.x, effect.y)

        -- Debug visualization
        if self.debug_mode then
            love.graphics.setColor(1, 0, 1, 0.5)
            love.graphics.circle("line", effect.x, effect.y, 20)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Clear all effects
function effects:clear()
    if self.debug_mode then
        print("Clearing " .. #self.active_effects .. " effects")
    end
    self.active_effects = {}
end

-- Get active effect count (for debugging)
function effects:getCount()
    return #self.active_effects
end

-- Toggle debug mode
function effects:toggleDebug()
    self.debug_mode = not self.debug_mode
    print("Effects debug mode: " .. tostring(self.debug_mode))
end

-- Test function - spawn effects at position
function effects:test(x, y)
    print("Testing all effects at (" .. x .. ", " .. y .. ")")
    self:spawn("blood", x, y - 40, 0, 40)
    self:spawn("spark", x, y + 40, math.pi / 4, 40)
    self:spawn("dust", x - 40, y, math.pi / 2, 40)
    self:spawn("slash", x + 40, y, 0, 40)
    print("Active effects: " .. self:getCount())
end

-- Preset combinations for common scenarios
function effects:spawnHitEffect(x, y, target_type, angle)
    if self.debug_mode then
        print(string.format("Spawning hit effect for %s at (%.1f, %.1f)", target_type, x, y))
    end

    if target_type == "enemy" or target_type == "player" then
        -- Blood + dust
        self:spawn("blood", x, y, angle, 35)
        self:spawn("dust", x, y, nil, 20)
    elseif target_type == "wall" then
        -- Dust only
        self:spawn("dust", x, y, nil, 40)
    end
end

function effects:spawnParryEffect(x, y, angle, is_perfect)
    if self.debug_mode then
        print(string.format("Spawning parry effect (%s) at (%.1f, %.1f)",
            is_perfect and "PERFECT" or "normal", x, y))
    end

    -- Sparks for parry
    local particle_count = is_perfect and 50 or 35
    self:spawn("spark", x, y, angle, particle_count)
end

function effects:spawnWeaponTrail(x, y, angle)
    if self.debug_mode then
        print(string.format("Spawning weapon trail at (%.1f, %.1f)", x, y))
    end

    -- Slash trail for weapon swing
    self:spawn("slash", x, y, angle, 20)
end

-- Initialize on require
effects:init()

return effects

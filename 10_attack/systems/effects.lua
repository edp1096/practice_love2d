-- systems/effects.lua
-- Central effect management system for all visual effects

local effects = {}

effects.active_effects = {}
effects.particle_systems = {}

-- Create particle image (used by all particle systems)
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
    local particle_img = createParticleImage(8)
    local ps = love.graphics.newParticleSystem(particle_img, 50)
    
    ps:setParticleLifetime(0.3, 0.6)
    ps:setEmissionRate(0)
    ps:setSizes(1.5, 2, 1, 0.5, 0)
    
    -- Red blood colors
    ps:setColors(
        0.9, 0.1, 0.1, 1,    -- Bright red
        0.8, 0.0, 0.0, 0.9,  -- Dark red
        0.6, 0.0, 0.0, 0.7,
        0.4, 0.0, 0.0, 0.3,
        0.2, 0.0, 0.0, 0     -- Fade out
    )
    
    ps:setLinearDamping(2, 4)
    ps:setSpeed(80, 150)
    ps:setSpread(math.pi * 2)
    ps:setRotation(0, math.pi * 2)
    
    return ps
end

-- Spark effect (yellow/white, metal clash)
function effects:createSparkSystem()
    local particle_img = createParticleImage(6)
    local ps = love.graphics.newParticleSystem(particle_img, 30)
    
    ps:setParticleLifetime(0.2, 0.4)
    ps:setEmissionRate(0)
    ps:setSizes(2, 2.5, 1.5, 0.5, 0)
    
    -- Yellow/white sparks
    ps:setColors(
        1, 1, 0.8, 1,        -- Bright white-yellow
        1, 1, 0.5, 0.9,      -- Yellow
        1, 0.8, 0.2, 0.7,    -- Orange
        0.8, 0.5, 0.1, 0.3,
        0.5, 0.3, 0, 0       -- Fade out
    )
    
    ps:setLinearDamping(3, 6)
    ps:setSpeed(100, 200)
    ps:setSpread(math.pi / 3)  -- Narrow cone
    ps:setRotation(0, math.pi * 2)
    
    return ps
end

-- Dust effect (gray/brown, impact on ground)
function effects:createDustSystem()
    local particle_img = createParticleImage(10)
    local ps = love.graphics.newParticleSystem(particle_img, 40)
    
    ps:setParticleLifetime(0.4, 0.8)
    ps:setEmissionRate(0)
    ps:setSizes(2, 3, 4, 3, 0)
    
    -- Gray/brown dust
    ps:setColors(
        0.6, 0.5, 0.4, 0.8,  -- Light brown
        0.5, 0.4, 0.3, 0.6,  -- Medium brown
        0.4, 0.3, 0.2, 0.4,  -- Dark brown
        0.3, 0.2, 0.1, 0.2,
        0.2, 0.1, 0, 0       -- Fade out
    )
    
    ps:setLinearDamping(1, 3)
    ps:setSpeed(50, 120)
    ps:setSpread(math.pi)  -- Spread upward
    ps:setRotation(0, math.pi * 2)
    
    return ps
end

-- Slash trail effect (cyan/white, sword trail)
function effects:createSlashSystem()
    local particle_img = createParticleImage(8)
    local ps = love.graphics.newParticleSystem(particle_img, 40)
    
    ps:setParticleLifetime(0.15, 0.3)
    ps:setEmissionRate(0)
    ps:setSizes(2, 2.5, 2, 1, 0)
    
    -- Cyan/white slash trail
    ps:setColors(
        0.8, 1, 1, 1,        -- Bright cyan-white
        0.5, 0.9, 1, 0.9,    -- Cyan
        0.3, 0.7, 0.9, 0.6,  -- Blue-cyan
        0.2, 0.5, 0.7, 0.3,
        0.1, 0.3, 0.5, 0     -- Fade out
    )
    
    ps:setLinearDamping(2, 4)
    ps:setSpeed(60, 100)
    ps:setSpread(math.pi / 4)  -- Narrow spread
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
end

-- Spawn an effect at a position
function effects:spawn(effect_type, x, y, angle, particle_count)
    if not self.particle_systems[effect_type] then
        print("Warning: Unknown effect type: " .. tostring(effect_type))
        return
    end
    
    particle_count = particle_count or 20
    
    -- Clone particle system for this instance
    local ps = self.particle_systems[effect_type]:clone()
    
    -- Set position
    ps:setPosition(x, y)
    
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
        lifetime = 2.0,  -- Max lifetime before cleanup
        time = 0
    })
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
            table.remove(self.active_effects, i)
        end
    end
end

-- Draw all active effects
function effects:draw()
    love.graphics.setColor(1, 1, 1, 1)
    for _, effect in ipairs(self.active_effects) do
        love.graphics.draw(effect.ps, effect.x, effect.y)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

-- Clear all effects
function effects:clear()
    self.active_effects = {}
end

-- Get active effect count (for debugging)
function effects:getCount()
    return #self.active_effects
end

-- Preset combinations for common scenarios
function effects:spawnHitEffect(x, y, target_type, angle)
    if target_type == "enemy" or target_type == "player" then
        -- Blood + dust
        self:spawn("blood", x, y, angle, 25)
        self:spawn("dust", x, y, nil, 15)
    elseif target_type == "wall" then
        -- Dust only
        self:spawn("dust", x, y, nil, 30)
    end
end

function effects:spawnParryEffect(x, y, angle, is_perfect)
    -- Sparks for parry
    local particle_count = is_perfect and 40 or 25
    self:spawn("spark", x, y, angle, particle_count)
end

function effects:spawnWeaponTrail(x, y, angle)
    -- Slash trail for weapon swing
    self:spawn("slash", x, y, angle, 15)
end

-- Initialize on require
effects:init()

return effects

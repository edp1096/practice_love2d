-- engine/effects/particles/systems.lua
-- Particle system definitions (blood, spark, dust, slash)

local systems = {}

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
function systems.createBloodSystem()
    local particle_img = createParticleImage(12)
    local ps = love.graphics.newParticleSystem(particle_img, 60)

    ps:setParticleLifetime(0.5, 1.0)
    ps:setEmissionRate(0)
    ps:setSizes(2, 3, 2, 1, 0)

    ps:setColors(
        1, 0.1, 0.1, 1,
        0.9, 0.0, 0.0, 1,
        0.7, 0.0, 0.0, 0.8,
        0.5, 0.0, 0.0, 0.5,
        0.3, 0.0, 0.0, 0
    )

    ps:setLinearDamping(1, 3)
    ps:setSpeed(100, 180)
    ps:setSpread(math.pi * 2)
    ps:setRotation(0, math.pi * 2)

    return ps
end

-- Spark effect (yellow/white, metal clash)
function systems.createSparkSystem()
    local particle_img = createParticleImage(10)
    local ps = love.graphics.newParticleSystem(particle_img, 50)

    ps:setParticleLifetime(0.3, 0.6)
    ps:setEmissionRate(0)
    ps:setSizes(2.5, 3, 2, 1, 0)

    ps:setColors(
        1, 1, 1, 1,
        1, 1, 0.6, 1,
        1, 0.9, 0.3, 0.9,
        0.9, 0.6, 0.1, 0.5,
        0.6, 0.4, 0, 0
    )

    ps:setLinearDamping(2, 5)
    ps:setSpeed(120, 250)
    ps:setSpread(math.pi / 3)
    ps:setRotation(0, math.pi * 2)

    return ps
end

-- Dust effect (gray/brown, impact on ground)
function systems.createDustSystem()
    local particle_img = createParticleImage(14)
    local ps = love.graphics.newParticleSystem(particle_img, 50)

    ps:setParticleLifetime(0.6, 1.2)
    ps:setEmissionRate(0)
    ps:setSizes(3, 4, 5, 3, 0)

    ps:setColors(
        0.7, 0.6, 0.5, 0.9,
        0.6, 0.5, 0.4, 0.7,
        0.5, 0.4, 0.3, 0.5,
        0.4, 0.3, 0.2, 0.3,
        0.3, 0.2, 0.1, 0
    )

    ps:setLinearDamping(0.5, 2)
    ps:setSpeed(60, 140)
    ps:setSpread(math.pi)
    ps:setRotation(0, math.pi * 2)

    return ps
end

-- Slash trail effect (cyan/white, sword trail)
function systems.createSlashSystem()
    local particle_img = createParticleImage(12)
    local ps = love.graphics.newParticleSystem(particle_img, 50)

    ps:setParticleLifetime(0.2, 0.4)
    ps:setEmissionRate(0)
    ps:setSizes(2.5, 3, 2.5, 1, 0)

    ps:setColors(
        1, 1, 1, 1,
        0.6, 1, 1, 1,
        0.4, 0.8, 1, 0.8,
        0.3, 0.6, 0.9, 0.4,
        0.2, 0.4, 0.7, 0
    )

    ps:setLinearDamping(1, 3)
    ps:setSpeed(80, 120)
    ps:setSpread(math.pi / 4)
    ps:setRotation(0, math.pi * 2)

    return ps
end

return systems

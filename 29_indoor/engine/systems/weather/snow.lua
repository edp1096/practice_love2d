-- engine/systems/weather/snow.lua
-- Snow weather effect for TOP-DOWN view
-- Snow appears across entire screen, drifting gently

local snow = {}

-- Particle system
local snow_system = nil
local snow_image = nil

-- Virtual screen size
local VW, VH = 960, 540

-- Snow configuration
local SNOW_EMIT_RATE = 150
local SNOW_LIFETIME = 4.0         -- Longer lifetime for slow drift
local SNOW_SPEED = 40             -- Slow movement
local SNOW_DRIFT = 20             -- Horizontal sway

-- Create snowflake image
local function createSnowImage()
    if snow_image then return end

    -- Snowflake: 8x8 pixel soft circle
    local imageData = love.image.newImageData(8, 8)
    imageData:mapPixel(function(x, y)
        local cx, cy = 4, 4
        local dist = math.sqrt((x - cx)^2 + (y - cy)^2)

        local alpha = 0
        if dist < 2.5 then
            alpha = 0.95 - (dist / 2.5) * 0.3
        elseif dist < 3.5 then
            alpha = 0.65 - ((dist - 2.5) / 1.0) * 0.4
        elseif dist < 4.5 then
            alpha = 0.25 - ((dist - 3.5) / 1.0) * 0.25
        end

        return 1.0, 1.0, 1.0, math.max(0, alpha)
    end)
    snow_image = love.graphics.newImage(imageData)
    snow_image:setFilter("linear", "linear")
end

-- Initialize snow effect
function snow:initialize(intensity)
    intensity = intensity or 1.0

    createSnowImage()

    snow_system = love.graphics.newParticleSystem(snow_image, 1000)

    snow_system:setParticleLifetime(SNOW_LIFETIME * 0.7, SNOW_LIFETIME)
    snow_system:setEmissionRate(SNOW_EMIT_RATE * intensity)

    -- TOP-DOWN: Emit across ENTIRE screen area
    snow_system:setEmissionArea("uniform", VW / 2, VH / 2, 0, false)

    -- Gentle diagonal drift (mostly down-right)
    snow_system:setDirection(math.rad(80))
    snow_system:setSpread(math.rad(30))

    snow_system:setSpeed(SNOW_SPEED * 0.6, SNOW_SPEED * 1.4)

    -- Gentle sway
    snow_system:setLinearAcceleration(-SNOW_DRIFT, 5, SNOW_DRIFT, 15)

    -- Size variation for depth effect
    snow_system:setSizes(1.4, 1.2, 1.0, 0.7)

    -- Gentle rotation
    snow_system:setRotation(0, math.rad(360))
    snow_system:setSpin(math.rad(-15), math.rad(15))

    -- Pure white, gradual fade
    snow_system:setColors(
        1.0, 1.0, 1.0, 0.85,
        1.0, 1.0, 1.0, 0.7,
        1.0, 1.0, 1.0, 0.4,
        1.0, 1.0, 1.0, 0.0
    )

    snow_system:start()

    -- Pre-fill entire screen
    local prefill = math.floor(SNOW_EMIT_RATE * SNOW_LIFETIME * 0.6)
    snow_system:emit(prefill)
end

-- Update
function snow:update(dt, intensity)
    intensity = intensity or 1.0

    if snow_system then
        snow_system:setEmissionRate(SNOW_EMIT_RATE * intensity)
        snow_system:update(dt)
    end
end

-- Draw
function snow:draw(intensity)
    if not snow_system then return end

    local display = require "engine.core.display"
    display:Attach()

    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)

    -- Draw snow at screen center (emission covers full screen)
    love.graphics.draw(snow_system, VW / 2, VH / 2)

    display:Detach()
end

-- Cleanup
function snow:cleanup()
    if snow_system then
        snow_system:stop()
        snow_system = nil
    end
end

return snow

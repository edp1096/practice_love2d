-- engine/systems/weather/storm.lua
-- Storm weather effect for TOP-DOWN view
-- Heavy rain with strong wind, appears across entire screen
-- Splashes are in WORLD coordinates (don't follow camera)

local constants = require "engine.core.constants"

local storm = {}

-- Particle systems
local rain_system = nil
local wind_system = nil
local rain_image = nil
local wind_image = nil

-- Manual splash system (world coordinates)
local splashes = {}
local ripple_image = nil

-- Camera reference (set externally)
storm.camera = nil
storm.no_splash_zones = {}

-- Check if point is inside any no-splash zone
local function isInNoSplashZone(x, y)
    for _, zone in ipairs(storm.no_splash_zones or {}) do
        if x >= zone.x and x <= zone.x + zone.w and
           y >= zone.y and y <= zone.y + zone.h then
            return true
        end
    end
    return false
end

-- Virtual screen size (from constants)
local VW, VH = constants.RENDER_WIDTH, constants.RENDER_HEIGHT

-- Storm configuration
local RAIN_EMIT_RATE = 1000
local RAIN_LIFETIME = 0.6
local RAIN_SPEED = 550
local RAIN_ANGLE = 60             -- More angled (strong wind)

-- Splash configuration
local SPLASH_RATE = 150
local SPLASH_TIMER = 0
local MAX_SPLASHES = 250

-- Wind configuration
local WIND_EMIT_RATE = 60
local WIND_LIFETIME = 0.6
local WIND_SPEED = 600

-- Create storm raindrop image
local function createRainImage()
    if rain_image then return end

    -- Longer diagonal streak for storm
    local imageData = love.image.newImageData(4, 12)
    imageData:mapPixel(function(x, y)
        local diag = (x / 4 + y / 12) / 2
        local dist_from_center = math.abs(diag - 0.5) * 2

        local alpha = 0.75 * (1 - dist_from_center)
        if y < 2 then alpha = alpha * (y / 2) end
        if y > 9 then alpha = alpha * ((12 - y) / 3) end

        return 0.7, 0.8, 0.95, math.max(0, alpha)
    end)
    rain_image = love.graphics.newImage(imageData)
    rain_image:setFilter("linear", "linear")
end

-- Create ripple image (larger, more visible ring)
local function createRippleImage()
    if ripple_image then return end

    -- Larger ripple: 24x12 pixel ellipse
    local imageData = love.image.newImageData(24, 12)
    imageData:mapPixel(function(x, y)
        local cx, cy = 12, 6
        local dx = (x - cx) / 11
        local dy = (y - cy) / 5
        local dist = math.sqrt(dx * dx + dy * dy)

        local alpha = 0
        -- Thicker, brighter ring
        if dist > 0.5 and dist < 1.0 then
            local ring_dist = math.abs(dist - 0.75)
            alpha = 0.8 - ring_dist * 2.5
        end
        -- Inner highlight
        if dist < 0.3 then
            alpha = math.max(alpha, 0.4 - dist)
        end
        -- Brighter color
        return 0.9, 0.95, 1.0, math.max(0, alpha)
    end)
    ripple_image = love.graphics.newImage(imageData)
    ripple_image:setFilter("linear", "linear")
end

-- Create wind streak image
local function createWindImage()
    if wind_image then return end

    local imageData = love.image.newImageData(24, 2)
    imageData:mapPixel(function(x, y)
        local alpha = 0.3
        if x < 5 then
            alpha = (x / 5) * 0.3
        elseif x > 18 then
            alpha = ((24 - x) / 6) * 0.3
        end
        return 0.85, 0.88, 0.92, alpha
    end)
    wind_image = love.graphics.newImage(imageData)
    wind_image:setFilter("linear", "linear")
end

-- Splash functions (world coordinates)
local function createSplash(world_x, world_y)
    return {
        x = world_x, y = world_y,  -- World coordinates
        time = 0,
        lifetime = 0.5,
        scale = 1.0 + math.random() * 0.7,
    }
end

local function updateSplash(splash, dt)
    splash.time = splash.time + dt
    local progress = splash.time / splash.lifetime
    splash.scale = (0.6 + progress * 2.2)
    return splash.time < splash.lifetime
end

local function drawSplash(splash)
    if not ripple_image then return end
    local progress = splash.time / splash.lifetime
    local alpha = 1 - (progress * progress)

    local w, h = ripple_image:getWidth(), ripple_image:getHeight()
    local scale = splash.scale / 3  -- 1/3 size
    love.graphics.setColor(0.95, 0.98, 1.0, alpha * 0.7)
    -- Draw at world coordinates (camera transform handles conversion)
    love.graphics.draw(ripple_image, splash.x, splash.y, 0, scale, scale * 0.5, w/2, h/2)
end

local function spawnSplash()
    -- Get camera position and scale for world coordinate calculation
    local cam_x, cam_y, cam_scale = 0, 0, 1
    if storm.camera then
        cam_x, cam_y = storm.camera:position()
        cam_scale = storm.camera.scale or 1
    end

    -- Visible world area = screen size / camera scale
    local visible_w = VW / cam_scale
    local visible_h = VH / cam_scale

    -- Random position within visible world area
    local world_x = cam_x + (math.random() - 0.5) * visible_w
    local world_y = cam_y + (math.random() - 0.5) * visible_h

    -- Skip if inside no-splash zone
    if isInNoSplashZone(world_x, world_y) then
        return
    end

    -- Reuse expired splash or create new
    for i, splash in ipairs(splashes) do
        if splash.time >= splash.lifetime then
            splashes[i] = createSplash(world_x, world_y)
            return
        end
    end

    if #splashes < MAX_SPLASHES then
        table.insert(splashes, createSplash(world_x, world_y))
    end
end

-- Initialize storm effect
function storm:initialize(intensity)
    intensity = intensity or 1.0

    createRainImage()
    createRippleImage()
    createWindImage()

    splashes = {}
    SPLASH_TIMER = 0

    -- === Storm Rain Particle System ===
    rain_system = love.graphics.newParticleSystem(rain_image, 2000)

    rain_system:setParticleLifetime(RAIN_LIFETIME * 0.8, RAIN_LIFETIME)
    rain_system:setEmissionRate(RAIN_EMIT_RATE * intensity)

    -- TOP-DOWN: Emit across ENTIRE screen
    rain_system:setEmissionArea("uniform", VW / 2, VH / 2, 0, false)

    -- Strong diagonal (wind blown)
    rain_system:setDirection(math.rad(RAIN_ANGLE))
    rain_system:setSpread(math.rad(8))

    rain_system:setSpeed(RAIN_SPEED * 0.9, RAIN_SPEED * 1.1)

    rain_system:setLinearAcceleration(60, 40, 100, 60)

    rain_system:setSizes(2.0, 1.8, 1.5)

    -- Rotate sprite to match direction
    rain_system:setRotation(math.rad(RAIN_ANGLE - 90))

    rain_system:setColors(
        0.75, 0.82, 0.95, 0.8,
        0.7, 0.78, 0.9, 0.6,
        0.6, 0.7, 0.85, 0.2
    )

    rain_system:start()

    local prefill = math.floor(RAIN_EMIT_RATE * RAIN_LIFETIME * 0.7)
    rain_system:emit(prefill)

    -- === Wind Streak Particle System ===
    wind_system = love.graphics.newParticleSystem(wind_image, 300)

    wind_system:setParticleLifetime(WIND_LIFETIME * 0.7, WIND_LIFETIME)
    wind_system:setEmissionRate(WIND_EMIT_RATE * intensity)

    -- Wind streaks across entire screen
    wind_system:setEmissionArea("uniform", VW / 2, VH / 2, 0, false)

    wind_system:setDirection(math.rad(10))
    wind_system:setSpread(math.rad(15))

    wind_system:setSpeed(WIND_SPEED * 0.8, WIND_SPEED * 1.2)

    wind_system:setLinearAcceleration(20, -10, 50, 10)

    wind_system:setSizes(1.2, 1.4, 1.0)

    wind_system:setColors(
        0.85, 0.88, 0.92, 0.3,
        0.8, 0.85, 0.9, 0.2,
        0.75, 0.8, 0.85, 0.0
    )

    wind_system:start()

    -- Pre-spawn splashes
    for i = 1, 60 do
        spawnSplash()
        if splashes[i] then
            splashes[i].time = math.random() * splashes[i].lifetime * 0.8
        end
    end
end

-- Update
function storm:update(dt, intensity)
    intensity = intensity or 1.0

    if rain_system then
        rain_system:setEmissionRate(RAIN_EMIT_RATE * intensity)
        rain_system:update(dt)
    end

    if wind_system then
        wind_system:setEmissionRate(WIND_EMIT_RATE * intensity)
        wind_system:update(dt)
    end

    for i = #splashes, 1, -1 do
        updateSplash(splashes[i], dt)
    end

    SPLASH_TIMER = SPLASH_TIMER + dt
    local spawn_interval = 1 / (SPLASH_RATE * intensity)
    while SPLASH_TIMER >= spawn_interval do
        SPLASH_TIMER = SPLASH_TIMER - spawn_interval
        spawnSplash()
    end
end

-- Draw
function storm:draw(intensity)
    if not rain_system then return end

    local display = require "engine.core.display"

    -- Draw storm particles in screen space
    display:Attach()
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)

    -- Draw wind streaks (background)
    if wind_system then
        love.graphics.draw(wind_system, VW / 2, VH / 2)
    end

    -- Draw rain at screen center
    love.graphics.draw(rain_system, VW / 2, VH / 2)
    love.graphics.setColor(1, 1, 1, 1)
    display:Detach()

    -- Draw splashes in world space using camera transform
    if self.camera then
        self.camera:attach()
        love.graphics.setBlendMode("alpha")
        for _, splash in ipairs(splashes) do
            if splash.time < splash.lifetime then
                drawSplash(splash)
            end
        end
        love.graphics.setColor(1, 1, 1, 1)
        self.camera:detach()
    end
end

-- Cleanup
function storm:cleanup()
    if rain_system then
        rain_system:stop()
        rain_system = nil
    end
    if wind_system then
        wind_system:stop()
        wind_system = nil
    end
    splashes = {}
    SPLASH_TIMER = 0
end

return storm

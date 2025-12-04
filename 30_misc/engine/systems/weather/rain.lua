-- engine/systems/weather/rain.lua
-- Rain weather effect for TOP-DOWN view
-- Rain appears across entire screen, moving diagonally (wind effect)
-- Splashes are in WORLD coordinates (don't follow camera)

local constants = require "engine.core.constants"

local rain = {}

-- Particle systems
local rain_system = nil
local rain_image = nil

-- Manual splash system (world coordinates)
local splashes = {}
local ripple_image = nil

-- Camera reference (set externally)
rain.camera = nil
rain.no_splash_zones = {}

-- Check if point is inside any no-splash zone
local function isInNoSplashZone(x, y)
    for _, zone in ipairs(rain.no_splash_zones or {}) do
        if x >= zone.x and x <= zone.x + zone.w and
           y >= zone.y and y <= zone.y + zone.h then
            return true
        end
    end
    return false
end

-- Virtual screen size (from constants)
local VW, VH = constants.RENDER_WIDTH, constants.RENDER_HEIGHT

-- Rain configuration
local RAIN_EMIT_RATE = 600
local RAIN_LIFETIME = 0.8
local RAIN_SPEED = 400            -- Diagonal movement speed
local RAIN_ANGLE = 70             -- Degrees from horizontal (70 = mostly down, some right)

-- Splash configuration
local SPLASH_RATE = 100           -- More splashes
local SPLASH_TIMER = 0
local MAX_SPLASHES = 200

-- Create raindrop image (diagonal streak for top-down)
local function createRainImage()
    if rain_image then return end

    -- Raindrop: 4x10 diagonal streak
    local imageData = love.image.newImageData(4, 10)
    imageData:mapPixel(function(x, y)
        -- Diagonal line from top-left to bottom-right
        local diag = (x / 4 + y / 10) / 2
        local dist_from_center = math.abs(diag - 0.5) * 2

        local alpha = 0.7 * (1 - dist_from_center)
        -- Fade at ends
        if y < 2 then alpha = alpha * (y / 2) end
        if y > 7 then alpha = alpha * ((10 - y) / 3) end

        return 0.8, 0.88, 1.0, math.max(0, alpha)
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
    if rain.camera then
        cam_x, cam_y = rain.camera:position()
        cam_scale = rain.camera.scale or 1
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

-- Initialize rain effect
function rain:initialize(intensity)
    intensity = intensity or 1.0

    createRainImage()
    createRippleImage()

    splashes = {}
    SPLASH_TIMER = 0

    -- === Rain Particle System ===
    rain_system = love.graphics.newParticleSystem(rain_image, 1500)

    rain_system:setParticleLifetime(RAIN_LIFETIME * 0.8, RAIN_LIFETIME)
    rain_system:setEmissionRate(RAIN_EMIT_RATE * intensity)

    -- TOP-DOWN: Emit across ENTIRE screen area
    rain_system:setEmissionArea("uniform", VW / 2, VH / 2, 0, false)

    -- Diagonal direction (wind effect)
    rain_system:setDirection(math.rad(RAIN_ANGLE))
    rain_system:setSpread(math.rad(10))

    rain_system:setSpeed(RAIN_SPEED * 0.9, RAIN_SPEED * 1.1)

    -- Slight acceleration variation
    rain_system:setLinearAcceleration(20, 30, 40, 50)

    rain_system:setSizes(1.6, 1.4, 1.2)

    -- Rotate sprite to match movement direction
    rain_system:setRotation(math.rad(RAIN_ANGLE - 90))

    rain_system:setColors(
        0.85, 0.9, 1.0, 0.7,
        0.8, 0.88, 1.0, 0.5,
        0.75, 0.85, 0.95, 0.2
    )

    rain_system:start()

    -- Pre-fill entire screen
    local prefill = math.floor(RAIN_EMIT_RATE * RAIN_LIFETIME * 0.8)
    rain_system:emit(prefill)

    -- Pre-spawn splashes across screen
    for i = 1, 40 do
        spawnSplash()
        if splashes[i] then
            splashes[i].time = math.random() * splashes[i].lifetime * 0.8
        end
    end
end

-- Update
function rain:update(dt, intensity)
    intensity = intensity or 1.0

    if rain_system then
        rain_system:setEmissionRate(RAIN_EMIT_RATE * intensity)
        rain_system:update(dt)
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
function rain:draw(intensity)
    if not rain_system then return end

    local display = require "engine.core.display"

    -- Draw rain particles in screen space
    display:Attach()
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
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
function rain:cleanup()
    if rain_system then
        rain_system:stop()
        rain_system = nil
    end
    splashes = {}
    SPLASH_TIMER = 0
end

return rain

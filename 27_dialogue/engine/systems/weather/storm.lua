-- engine/systems/weather/storm.lua
-- Storm weather effect - heavy rain with wind gusts

local storm = {}

-- Particle systems
local rain_system = nil
local wind_system = nil
local particle_image = nil
local wind_image = nil

-- Configuration
local BASE_RAIN_RATE = 2000       -- Particles per second (double rain!)
local RAIN_LIFETIME = 1.5         -- Shorter lifetime (faster drops)
local FALL_SPEED = 700            -- Faster than normal rain
local WIND_FACTOR = 60            -- Strong horizontal wind

-- Wind gust configuration
local WIND_EMIT_RATE = 100
local WIND_LIFETIME = 1.0
local WIND_SPEED = 400

-- Initialize storm effect
function storm:initialize(intensity)
  intensity = intensity or 1.0

  -- Create raindrop image if needed
  if not particle_image then
    -- Raindrop (4x16 pixel vertical line)
    local imageData = love.image.newImageData(4, 16)
    imageData:mapPixel(function(x, y, r, g, b, a)
      local alpha = 0.8
      if y < 2 or y > 13 then
        alpha = 0.4  -- Fade at ends
      end
      -- Darker blue-gray for storm
      return 0.7, 0.8, 0.9, alpha
    end)
    particle_image = love.graphics.newImage(imageData)
    particle_image:setFilter("nearest", "nearest")
  end

  -- Create wind streak image if needed
  if not wind_image then
    -- Wind streak (16x2 pixel horizontal line)
    local imageData = love.image.newImageData(16, 2)
    imageData:mapPixel(function(x, y, r, g, b, a)
      local alpha = 0.3
      if x < 3 or x > 12 then
        alpha = 0.1  -- Fade at ends
      end
      -- Light gray for wind
      return 0.9, 0.9, 0.9, alpha
    end)
    wind_image = love.graphics.newImage(imageData)
    wind_image:setFilter("nearest", "nearest")
  end

  -- Create rain particle system (need enough for emission_rate × lifetime)
  rain_system = love.graphics.newParticleSystem(particle_image, 4000)

  -- Configure rain particles (heavier than normal rain)
  rain_system:setParticleLifetime(RAIN_LIFETIME)
  rain_system:setEmissionRate(BASE_RAIN_RATE * intensity)

  local vw, vh = 960, 540
  rain_system:setEmissionArea("uniform", vw * 0.8, 0)  -- Wider area to cover wind drift

  -- Angled direction (wind blown)
  rain_system:setDirection(math.rad(110))  -- 20 degrees from vertical (90 + 20)
  rain_system:setSpread(math.rad(10))

  -- Faster speed
  rain_system:setSpeed(FALL_SPEED, FALL_SPEED + 200)

  -- Strong wind acceleration
  rain_system:setLinearAcceleration(WIND_FACTOR, 100, WIND_FACTOR * 1.5, 150)

  -- Size variation
  rain_system:setSizes(2.5, 2.2, 1.8)

  -- Darker storm colors
  rain_system:setColors(
    0.8, 0.85, 0.95, 0.9,  -- Start: dark blue-gray
    0.7, 0.8, 0.9, 0.7,    -- Mid: darker
    0.6, 0.7, 0.85, 0.3    -- End: fade out
  )

  rain_system:start()

  -- Create wind particle system
  wind_system = love.graphics.newParticleSystem(wind_image, 500)

  wind_system:setParticleLifetime(WIND_LIFETIME)
  wind_system:setEmissionRate(WIND_EMIT_RATE * intensity)

  wind_system:setEmissionArea("uniform", 0, vh / 2)

  -- Horizontal direction (left to right)
  wind_system:setDirection(math.rad(0))
  wind_system:setSpread(math.rad(20))

  -- Fast horizontal speed
  wind_system:setSpeed(WIND_SPEED, WIND_SPEED + 200)

  -- No gravity
  wind_system:setLinearAcceleration(50, -20, 100, 20)

  -- Size variation for wind streaks
  wind_system:setSizes(1.5, 1.8, 1.2)

  -- Light gray wind color
  wind_system:setColors(
    0.9, 0.9, 0.9, 0.4,   -- Start: visible
    0.85, 0.85, 0.85, 0.2, -- Mid: fading
    0.8, 0.8, 0.8, 0.0    -- End: transparent
  )

  wind_system:start()
end

-- Update
function storm:update(dt, intensity)
  intensity = intensity or 1.0

  if rain_system then
    rain_system:setEmissionRate(BASE_RAIN_RATE * intensity)
    rain_system:update(dt)
  end

  if wind_system then
    wind_system:setEmissionRate(WIND_EMIT_RATE * intensity)
    wind_system:update(dt)
  end
end

-- Draw
function storm:draw(intensity)
  if not rain_system and not wind_system then return end

  local display = require "engine.core.display"
  display:Attach()

  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)

  local vw, vh = 960, 540

  -- Draw wind streaks first (background)
  if wind_system then
    love.graphics.draw(wind_system, 0, vh / 2)
  end

  -- Draw rain on top (spawn from right since wind blows left)
  if rain_system then
    love.graphics.draw(rain_system, vw * 3 / 4, -50)  -- Right side to cover wind drift
  end

  display:Detach()
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
end

return storm

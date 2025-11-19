-- engine/systems/weather/snow.lua
-- Snow weather effect using particle system

local snow = {}

-- Particle system
local particle_system = nil
local particle_image = nil

-- Configuration
local BASE_EMIT_RATE = 300        -- Particles per second at full intensity (less than rain)
local PARTICLE_LIFETIME = 8.0     -- How long particles live (long enough to reach bottom)
local FALL_SPEED = 80             -- Pixels per second (much slower than rain)
local WIND_FACTOR = 15            -- Horizontal drift (gentle sway)

-- Initialize snow effect
function snow:initialize(intensity)
  intensity = intensity or 1.0

  -- Create snowflake image if needed
  if not particle_image then
    -- Create snowflake image (8x8 pixel)
    local imageData = love.image.newImageData(8, 8)
    imageData:mapPixel(function(x, y, r, g, b, a)
      -- Center distance for circular shape
      local cx, cy = 4, 4
      local dist = math.sqrt((x - cx)^2 + (y - cy)^2)

      -- Create soft circular snowflake
      local alpha = 0
      if dist < 3 then
        alpha = 0.9 - (dist / 3) * 0.4  -- Center is brighter
      elseif dist < 4 then
        alpha = 0.3  -- Soft edge
      end

      -- Pure white
      return 1.0, 1.0, 1.0, alpha
    end)
    particle_image = love.graphics.newImage(imageData)
    particle_image:setFilter("linear", "linear")  -- Soft filtering for snow
  end

  -- Create particle system (need enough for emission_rate × lifetime)
  particle_system = love.graphics.newParticleSystem(particle_image, 3000)

  -- Configure particles
  particle_system:setParticleLifetime(PARTICLE_LIFETIME)
  particle_system:setEmissionRate(BASE_EMIT_RATE * intensity)

  -- Area to emit from (full screen width, above screen)
  local vw, vh = 960, 540  -- Virtual resolution
  particle_system:setEmissionArea("uniform", vw / 2, 0)

  -- Direction: downward with gentle drift
  particle_system:setDirection(math.rad(90))
  particle_system:setSpread(math.rad(15))  -- More spread than rain

  -- Speed (slower than rain)
  particle_system:setSpeed(FALL_SPEED, FALL_SPEED + 40)

  -- Linear acceleration (gentle wind sway)
  particle_system:setLinearAcceleration(-WIND_FACTOR, 0, WIND_FACTOR, 20)

  -- Size variation (snowflakes of different sizes)
  particle_system:setSizes(1.5, 1.2, 0.8, 0.5)

  -- Gentle rotation for snowflake effect
  particle_system:setRotation(0, math.rad(360))
  particle_system:setSpin(math.rad(-30), math.rad(30))

  -- Color stays white but fades out slowly
  particle_system:setColors(
    1.0, 1.0, 1.0, 0.9,   -- Start: bright white
    1.0, 1.0, 1.0, 0.7,   -- Mid: still bright
    1.0, 1.0, 1.0, 0.4,   -- Late: fading
    1.0, 1.0, 1.0, 0.0    -- End: transparent
  )

  -- Start emitting
  particle_system:start()
end

-- Update
function snow:update(dt, intensity)
  intensity = intensity or 1.0

  if particle_system then
    -- Update emission rate based on intensity
    particle_system:setEmissionRate(BASE_EMIT_RATE * intensity)

    -- Update particles
    particle_system:update(dt)
  end
end

-- Draw
function snow:draw(intensity)
  if not particle_system then return end

  -- Draw particle system (uses display coordinates)
  local display = require "engine.core.display"
  display:Attach()

  -- Simple alpha blend
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)

  -- Position at top of virtual screen
  local vw, vh = 960, 540
  love.graphics.draw(particle_system, vw / 2, -50)

  display:Detach()
end

-- Cleanup
function snow:cleanup()
  if particle_system then
    particle_system:stop()
    particle_system = nil
  end
end

return snow

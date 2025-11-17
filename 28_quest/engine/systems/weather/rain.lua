-- engine/systems/weather/rain.lua
-- Rain weather effect using particle system

local rain = {}

-- Particle system
local particle_system = nil
local particle_image = nil

-- Configuration
local BASE_EMIT_RATE = 1000     -- Particles per second at full intensity
local PARTICLE_LIFETIME = 2.0   -- How long particles live
local FALL_SPEED = 500          -- Pixels per second
local WIND_FACTOR = 20          -- Horizontal drift

-- Initialize rain effect
function rain:initialize(intensity)
  intensity = intensity or 1.0

  -- Create particle image if needed
  if not particle_image then
    -- Create raindrop image (4x16 pixel vertical line - more visible)
    local imageData = love.image.newImageData(4, 16)
    imageData:mapPixel(function(x, y, r, g, b, a)
      -- White raindrop with gradient
      local alpha = 0.8
      if y < 2 or y > 13 then
        alpha = 0.4  -- Fade at ends
      end
      return 0.9, 0.95, 1.0, alpha
    end)
    particle_image = love.graphics.newImage(imageData)
    particle_image:setFilter("nearest", "nearest")  -- Sharp pixels
  end

  -- Create particle system (need enough for emission_rate × lifetime)
  particle_system = love.graphics.newParticleSystem(particle_image, 3000)

  -- Configure particles
  particle_system:setParticleLifetime(PARTICLE_LIFETIME)
  particle_system:setEmissionRate(BASE_EMIT_RATE * intensity)

  -- Area to emit from (full screen width, minimal height)
  -- Particles spawn across entire width, at same Y position
  local vw, vh = 960, 540  -- Virtual resolution
  particle_system:setEmissionArea("uniform", vw / 2, 0)

  -- Direction: downward (90 degrees = down in LÖVE)
  particle_system:setDirection(math.rad(90))
  particle_system:setSpread(math.rad(5))

  -- Speed (fast enough to fall across screen)
  particle_system:setSpeed(FALL_SPEED, FALL_SPEED + 150)

  -- Linear acceleration (gravity + slight wind)
  particle_system:setLinearAcceleration(WIND_FACTOR, 50, WIND_FACTOR * 1.5, 100)

  -- Size variation (make bigger!)
  particle_system:setSizes(2.0, 1.8, 1.5)

  -- NO rotation - raindrops should be vertical!

  -- Color with less fade (stay visible longer)
  particle_system:setColors(
    1.0, 1.0, 1.0, 0.9,   -- Start: bright white
    0.9, 0.95, 1.0, 0.7,  -- Mid: light blue
    0.8, 0.9, 1.0, 0.3    -- End: fade out
  )

  -- Start emitting
  particle_system:start()
end

-- Update
function rain:update(dt, intensity)
  intensity = intensity or 1.0

  if particle_system then
    -- Update emission rate based on intensity
    particle_system:setEmissionRate(BASE_EMIT_RATE * intensity)

    -- Update particles
    particle_system:update(dt)
  end
end

-- Draw
function rain:draw(intensity)
  if not particle_system then return end

  -- Draw particle system (uses display coordinates)
  local display = require "engine.core.display"
  display:Attach()

  -- Simple alpha blend
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)

  -- Position at top of virtual screen (particles fall down from above)
  local vw, vh = 960, 540
  love.graphics.draw(particle_system, vw / 2, -50)

  display:Detach()
end

-- Cleanup
function rain:cleanup()
  if particle_system then
    particle_system:stop()
    particle_system = nil
  end
end

return rain

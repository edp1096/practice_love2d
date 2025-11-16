-- engine/systems/weather/fog.lua
-- Fog/mist weather effect using moving layers

local fog = {}

-- Fog layers (multiple overlapping circles moving at different speeds)
local layers = {}
local NUM_LAYERS = 8  -- Number of fog puffs

-- Configuration
local BASE_ALPHA = 0.15      -- Base opacity per layer at full intensity
local MOVE_SPEED = 10        -- Pixels per second
local FOG_COLOR = {0.9, 0.9, 0.95}  -- Light gray-blue

-- Layer data
local Layer = {}
Layer.__index = Layer

function Layer:new(x, y, radius, speed_x, speed_y)
  local layer = {
    x = x,
    y = y,
    radius = radius,
    speed_x = speed_x,
    speed_y = speed_y,
    offset_x = 0,
    offset_y = 0
  }
  setmetatable(layer, Layer)
  return layer
end

function Layer:update(dt)
  -- Move layer
  self.offset_x = self.offset_x + self.speed_x * dt
  self.offset_y = self.offset_y + self.speed_y * dt

  -- Wrap around (infinite scroll)
  local vw, vh = 960, 540
  if self.offset_x > vw then
    self.offset_x = self.offset_x - vw
  elseif self.offset_x < -vw then
    self.offset_x = self.offset_x + vw
  end

  if self.offset_y > vh then
    self.offset_y = self.offset_y - vh
  elseif self.offset_y < -vh then
    self.offset_y = self.offset_y + vh
  end
end

function Layer:draw(intensity)
  local vw, vh = 960, 540
  local alpha = BASE_ALPHA * intensity

  -- Draw layer with wrapped positions (tiled effect)
  for ox = -1, 1 do
    for oy = -1, 1 do
      local draw_x = self.x + self.offset_x + (ox * vw)
      local draw_y = self.y + self.offset_y + (oy * vh)

      -- Only draw if on screen (with margin)
      if draw_x > -self.radius and draw_x < vw + self.radius and
         draw_y > -self.radius and draw_y < vh + self.radius then

        -- Draw radial gradient (fog puff)
        love.graphics.setColor(FOG_COLOR[1], FOG_COLOR[2], FOG_COLOR[3], alpha)
        love.graphics.circle("fill", draw_x, draw_y, self.radius, 64)
      end
    end
  end
end

-- Initialize fog effect
function fog:initialize(intensity)
  intensity = intensity or 1.0
  layers = {}

  local vw, vh = 960, 540

  -- Create random fog layers
  for i = 1, NUM_LAYERS do
    local x = math.random(0, vw)
    local y = math.random(0, vh)
    local radius = math.random(150, 400)  -- Large fog puffs

    -- Random drift speed
    local speed_x = (math.random() - 0.5) * MOVE_SPEED * 2
    local speed_y = (math.random() - 0.5) * MOVE_SPEED * 2

    table.insert(layers, Layer:new(x, y, radius, speed_x, speed_y))
  end
end

-- Update
function fog:update(dt, intensity)
  intensity = intensity or 1.0

  for _, layer in ipairs(layers) do
    layer:update(dt)
  end
end

-- Draw
function fog:draw(intensity)
  if #layers == 0 then return end

  local display = require "engine.core.display"
  display:Attach()

  -- Enable additive blending for fog layers
  love.graphics.setBlendMode("alpha")

  -- Draw all layers
  for _, layer in ipairs(layers) do
    layer:draw(intensity)
  end

  -- Reset color and blend mode
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("alpha")

  display:Detach()
end

-- Cleanup
function fog:cleanup()
  layers = {}
end

return fog

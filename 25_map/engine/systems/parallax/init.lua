-- engine/systems/parallax/init.lua
-- Main parallax system for managing multiple background layers

local Layer = require "engine.systems.parallax.layer"

local parallax = {
  layers = {},
  active = false
}

-- Initialize parallax system with layers
-- layer_configs: array of layer config tables
function parallax:init(layer_configs)
  self:clear()

  if not layer_configs or #layer_configs == 0 then
    return
  end

  -- Create layers
  for _, config in ipairs(layer_configs) do
    local layer = Layer.new(config)
    if layer then
      table.insert(self.layers, layer)
    else
      print("Warning: Failed to create parallax layer for " .. (config.image or "unknown"))
    end
  end

  -- Sort layers by z_index (lower = behind, drawn first)
  table.sort(self.layers, function(a, b)
    return a.z_index < b.z_index
  end)

  self.active = true
end

-- Update all layers (auto-scroll)
function parallax:update(dt)
  if not self.active then return end

  for _, layer in ipairs(self.layers) do
    layer:update(dt)
  end
end

-- Draw all layers
-- camera: camera object with position() method (hump.camera)
-- screen_width, screen_height: viewport dimensions (optional, uses physical screen if not provided)
function parallax:draw(camera, screen_width, screen_height)
  if not self.active or #self.layers == 0 then return end

  -- Get camera position and scale
  local camera_x, camera_y = 0, 0
  local camera_scale = 1.0
  if camera then
    if camera.position then
      -- hump.camera style
      camera_x, camera_y = camera:position()
    elseif camera.x and camera.y then
      -- Direct field access
      camera_x, camera_y = camera.x, camera.y
    end

    -- Get camera scale (hump.camera stores it as 'scale' field)
    if camera.scale then
      camera_scale = camera.scale
    end
  end

  -- Get screen dimensions (use PHYSICAL screen size for proper parallax)
  if not screen_width or not screen_height then
    screen_width = love.graphics.getWidth()
    screen_height = love.graphics.getHeight()
  end


  -- Draw all layers in order (z_index sorted)
  for _, layer in ipairs(self.layers) do
    layer:draw(camera_x, camera_y, screen_width, screen_height, camera_scale)
  end
end

-- Check if parallax is active
function parallax:isActive()
  return self.active
end

-- Get number of layers
function parallax:getLayerCount()
  return #self.layers
end

-- Clear all layers
function parallax:clear()
  for _, layer in ipairs(self.layers) do
    layer:destroy()
  end
  self.layers = {}
  self.active = false
end

return parallax

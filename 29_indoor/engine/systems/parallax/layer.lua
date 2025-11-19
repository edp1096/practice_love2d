-- engine/systems/parallax/layer.lua
-- Individual parallax layer with infinite repeat logic

local Layer = {}
Layer.__index = Layer

-- Create a new parallax layer
-- config: {
--   image: string - path to image file
--   parallax_factor: number - camera movement multiplier (0.0 = fixed, 1.0 = normal)
--   z_index: number - rendering order (lower = behind)
--   repeat_x: boolean - horizontal repeat
--   repeat_y: boolean - vertical repeat
--   auto_scroll_x: number - automatic scroll speed (pixels/sec)
--   auto_scroll_y: number - automatic scroll speed (pixels/sec)
--   offset_x: number - initial X offset
--   offset_y: number - initial Y offset
-- }
function Layer.new(config)
  local self = setmetatable({}, Layer)

  -- Load image
  self.image_path = config.image

  -- Check if image file exists
  local file_info = love.filesystem.getInfo(config.image)
  if not file_info then
    print("ERROR: Parallax image not found: " .. config.image)
    return nil
  end

  -- Load image with error handling
  local success, result = pcall(love.graphics.newImage, config.image)
  if not success then
    print("ERROR: Failed to load parallax image: " .. config.image)
    print("  Reason: " .. tostring(result))
    return nil
  end

  self.image = result
  self.image:setWrap("repeat", "repeat")  -- Enable texture wrapping

  -- Image dimensions
  self.width = self.image:getWidth()
  self.height = self.image:getHeight()

  -- Parallax settings
  self.parallax_factor = config.parallax_factor or 0.5
  self.z_index = config.z_index or 0

  -- Repeat settings
  self.repeat_x = config.repeat_x ~= false  -- Default true
  self.repeat_y = config.repeat_y or false

  -- Auto scroll
  self.auto_scroll_x = config.auto_scroll_x or 0
  self.auto_scroll_y = config.auto_scroll_y or 0
  self.scroll_offset_x = 0
  self.scroll_offset_y = 0

  -- Position offsets
  self.offset_x = config.offset_x or 0
  self.offset_y = config.offset_y or 0

  return self
end

-- Update layer (auto-scroll)
function Layer:update(dt)
  if self.auto_scroll_x ~= 0 then
    self.scroll_offset_x = self.scroll_offset_x + (self.auto_scroll_x * dt)
  end

  if self.auto_scroll_y ~= 0 then
    self.scroll_offset_y = self.scroll_offset_y + (self.auto_scroll_y * dt)
  end
end

-- Draw layer with parallax effect
-- camera_x, camera_y: camera position in world coordinates
-- virtual_width, virtual_height: virtual screen dimensions (960x540)
function Layer:draw(camera_x, camera_y, virtual_width, virtual_height)
  -- Virtual coordinate space parallax
  -- parallax_factor: how much the layer scrolls with camera movement
  -- 0.0 = no scroll (fixed background), 1.0 = full scroll (moves with camera)

  -- Calculate parallax offset from camera movement
  local parallax_offset_x = camera_x * self.parallax_factor
  local parallax_offset_y = camera_y * self.parallax_factor

  -- Apply auto-scroll and manual offset
  local scroll_x = -parallax_offset_x + self.scroll_offset_x + self.offset_x
  local scroll_y = -parallax_offset_y + self.scroll_offset_y + self.offset_y

  -- Smooth infinite horizontal tiling (no tile snapping!)
  if self.repeat_x then
    -- Start from scroll_x position and extend left to cover virtual screen
    local start_x = scroll_x
    -- Move left until we're off-screen left edge
    while start_x > -self.width do
      start_x = start_x - self.width
    end

    -- Now draw from start_x rightward to cover entire virtual screen
    local x = start_x
    while x < virtual_width do
      if self.repeat_y then
        -- Vertical tiling
        local start_y = scroll_y
        while start_y > -self.height do
          start_y = start_y - self.height
        end
        local y = start_y
        while y < virtual_height do
          love.graphics.draw(self.image, x, y)
          y = y + self.height
        end
      else
        -- Only horizontal tiling
        love.graphics.draw(self.image, x, scroll_y)
      end
      x = x + self.width
    end
  else
    -- No repeat, single draw
    love.graphics.draw(self.image, scroll_x, scroll_y)
  end
end

-- Cleanup
function Layer:destroy()
  if self.image then
    self.image:release()
    self.image = nil
  end
end

return Layer

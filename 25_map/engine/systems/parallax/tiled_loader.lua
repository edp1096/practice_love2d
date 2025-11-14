-- engine/systems/parallax/tiled_loader.lua
-- Extract parallax layer information from Tiled maps (STI)

local tiled_loader = {}

-- Load parallax layers from Tiled map
-- map: STI map object
-- Returns: array of layer configs for parallax system
function tiled_loader.loadParallaxLayers(map)
  local layer_configs = {}

  if not map or not map.layers then
    return layer_configs
  end

  -- Look for "Parallax" object layer
  for _, layer in ipairs(map.layers) do
    if layer.type == "objectgroup" and layer.name == "Parallax" then
      -- Process objects in this layer
      if layer.objects then
        for _, obj in ipairs(layer.objects) do
          -- Check if object is a parallax background
          -- Support both obj.type and properties.Type (Tiled export variations)
          local is_parallax = obj.type == "parallax" or
                              (obj.properties and obj.properties.Type == "parallax")

          if is_parallax and obj.properties then
            local config = tiled_loader.parseParallaxObject(obj)
            if config then
              table.insert(layer_configs, config)
            end
          end
        end
      end
    end
  end

  return layer_configs
end

-- Parse a single parallax object from Tiled
-- obj: Tiled object with properties
-- Returns: layer config table or nil
function tiled_loader.parseParallaxObject(obj)
  local props = obj.properties

  -- Required: image path
  if not props.image then
    print("Warning: Parallax object '" .. (obj.name or "unnamed") .. "' missing 'image' property")
    return nil
  end

  -- Build layer config
  local config = {
    image = props.image,  -- Use full path from Tiled (e.g., "assets/backgrounds/layer1_sky.png")
    parallax_factor = tonumber(props.parallax_factor) or 0.5,
    z_index = tonumber(props.z_index) or 0,
    repeat_x = props.repeat_x ~= false,  -- Default true
    repeat_y = props.repeat_y or false,
    auto_scroll_x = tonumber(props.auto_scroll_x) or 0,
    auto_scroll_y = tonumber(props.auto_scroll_y) or 0,
    offset_x = tonumber(props.offset_x) or tonumber(obj.x) or 0,
    offset_y = tonumber(props.offset_y) or tonumber(obj.y) or 0
  }

  return config
end

return tiled_loader

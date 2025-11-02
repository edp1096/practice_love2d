-- systems/parallax.lua
-- Parallax background rendering system

local parallax = {}

function parallax:new()
    local instance = setmetatable({}, { __index = parallax })
    instance.layers = {}
    return instance
end

-- Add background layer from image file
function parallax:addLayer(image_path, scroll_speed_x, scroll_speed_y, z_order)
    z_order = z_order or #self.layers + 1
    scroll_speed_x = scroll_speed_x or 0.5
    scroll_speed_y = scroll_speed_y or scroll_speed_x

    local image = love.graphics.newImage(image_path)
    image:setWrap("repeat", "repeat")

    table.insert(self.layers, {
        image = image,
        scroll_x = scroll_speed_x,
        scroll_y = scroll_speed_y,
        z_order = z_order,
        offset_x = 0,
        offset_y = 0
    })

    -- Sort by z_order
    table.sort(self.layers, function(a, b) return a.z_order < b.z_order end)
end

-- Load parallax layers from Tiled map
function parallax:loadFromMap(map)
    if not map or not map.layers then return end

    for _, layer in ipairs(map.layers) do
        if layer.type == "imagelayer" and layer.image then
            local scroll_x = 1.0
            local scroll_y = 1.0
            local z_order = 0

            -- Read parallax properties
            if layer.properties then
                scroll_x = layer.properties.parallax_x or layer.properties.parallaxX or 1.0
                scroll_y = layer.properties.parallax_y or layer.properties.parallaxY or 1.0
                z_order = layer.properties.z_order or layer.properties.zOrder or 0
            end

            -- Skip if parallax is 1.0 (normal layer)
            if scroll_x ~= 1.0 or scroll_y ~= 1.0 then
                self:addLayerFromTiled(layer, scroll_x, scroll_y, z_order)
            end
        end
    end
end

-- Add layer from Tiled layer data
function parallax:addLayerFromTiled(layer, scroll_x, scroll_y, z_order)
    if not layer.image then return end

    table.insert(self.layers, {
        image = layer.image,
        scroll_x = scroll_x,
        scroll_y = scroll_y,
        z_order = z_order,
        offset_x = layer.offsetx or 0,
        offset_y = layer.offsety or 0,
        tiled_layer = layer
    })

    -- Sort by z_order
    table.sort(self.layers, function(a, b) return a.z_order < b.z_order end)
end

-- Draw all parallax layers
function parallax:draw(camera_x, camera_y, viewport_width, viewport_height)
    for _, layer in ipairs(self.layers) do
        local image = layer.image
        local iw, ih = image:getDimensions()

        -- Calculate parallax offset
        local offset_x = camera_x * layer.scroll_x + layer.offset_x
        local offset_y = camera_y * layer.scroll_y + layer.offset_y

        -- Calculate quad to create repeating effect
        local quad_x = offset_x % iw
        local quad_y = offset_y % ih

        -- Draw multiple times to cover viewport
        local tiles_x = math.ceil(viewport_width / iw) + 2
        local tiles_y = math.ceil(viewport_height / ih) + 2

        for tx = -1, tiles_x do
            for ty = -1, tiles_y do
                local draw_x = tx * iw - quad_x
                local draw_y = ty * ih - quad_y
                love.graphics.draw(image, draw_x, draw_y)
            end
        end
    end
end

-- Clear all layers
function parallax:clear()
    self.layers = {}
end

return parallax

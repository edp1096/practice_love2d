-- engine/lighting/init.lua
-- Lighting system manager (ambient, point lights, spotlights)

local Light = require "engine.lighting.light"

local lighting = {}

lighting.lights = {}
lighting.ambient_color = {0.3, 0.3, 0.4}  -- Default: slightly dark blue
lighting.canvas = nil
lighting.enabled = true

-- Ambient presets
lighting.AMBIENT_PRESETS = {
    day = {0.95, 0.95, 1.0},        -- Bright, slightly blue
    dusk = {0.7, 0.6, 0.8},         -- Dim, purple tint
    night = {0.05, 0.05, 0.15},     -- Very dark blue
    cave = {0.05, 0.05, 0.1},       -- Very dark
    indoor = {0.5, 0.5, 0.55},      -- Medium, neutral
    underground = {0.1, 0.1, 0.12}  -- Very dark, neutral
}

-- Initialize lighting system
function lighting:init()
    -- Create canvas for lighting
    local width, height = love.graphics.getDimensions()
    self.canvas = love.graphics.newCanvas(width, height)

    -- Create circular gradient image for lights
    local size = 256
    local imageData = love.image.newImageData(size, size)
    local center = size / 2

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local dx = x - center + 0.5
            local dy = y - center + 0.5
            local dist = math.sqrt(dx * dx + dy * dy)
            local normalized = dist / center

            if normalized > 1.0 then
                imageData:setPixel(x, y, 0, 0, 0, 0)  -- Transparent
            else
                local alpha = (1.0 - normalized) ^ 2  -- Quadratic falloff
                imageData:setPixel(x, y, 1, 1, 1, alpha)
            end
        end
    end

    self.light_image = love.graphics.newImage(imageData)
end

-- Set ambient light color
function lighting:setAmbient(preset_or_color, g, b)
    if type(preset_or_color) == "string" then
        -- Use preset
        local preset = self.AMBIENT_PRESETS[preset_or_color]
        if preset then
            self.ambient_color = {preset[1], preset[2], preset[3]}
        else
            dprint("WARNING: Unknown ambient preset: " .. preset_or_color)
        end
    elseif type(preset_or_color) == "table" then
        -- Direct color table
        self.ambient_color = {preset_or_color[1], preset_or_color[2], preset_or_color[3]}
    elseif g and b then
        -- RGB parameters
        self.ambient_color = {preset_or_color, g, b}
    end
end

-- Add a light source
function lighting:addLight(config)
    local light = Light.new(config)
    table.insert(self.lights, light)
    return light
end

-- Remove a specific light
function lighting:removeLight(light)
    for i, l in ipairs(self.lights) do
        if l == light then
            table.remove(self.lights, i)
            return true
        end
    end
    return false
end

-- Remove all lights
function lighting:clearLights()
    self.lights = {}
end

-- Update all lights
function lighting:update(dt)
    for _, light in ipairs(self.lights) do
        if light.enabled then
            light:update(dt)
        end
    end
end

-- Draw lighting (call after camera:detach(), before display:Attach())
function lighting:draw(camera)
    if not self.enabled then
        return
    end

    -- Draw to lighting canvas in camera space
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(self.ambient_color[1], self.ambient_color[2], self.ambient_color[3], 1)

    -- Apply camera transformation to lighting canvas
    if camera then
        camera:attach()
    end

    -- Draw all lights with additive blending
    love.graphics.setBlendMode("add")

    for _, light in ipairs(self.lights) do
        if light.enabled then
            self:drawLight(light, camera)
        end
    end

    love.graphics.setBlendMode("alpha")

    if camera then
        camera:detach()
    end

    love.graphics.setCanvas()

    -- Composite lighting onto screen with multiply blend
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setBlendMode("multiply", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, 0, 0)
    love.graphics.setBlendMode("alpha")
    love.graphics.pop()

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a single light
function lighting:drawLight(light, camera)
    local world_x, world_y = light.x, light.y
    local intensity = light:getCurrentIntensity()

    if light.type == "point" then
        -- Draw circular gradient image with color tint
        love.graphics.setColor(
            light.color[1] * intensity,
            light.color[2] * intensity,
            light.color[3] * intensity,
            1
        )

        -- Draw in world space (camera already applied)
        -- radius is in world units, no need to scale
        love.graphics.draw(
            self.light_image,
            world_x,
            world_y,
            0,
            light.radius * 2 / self.light_image:getWidth(),
            light.radius * 2 / self.light_image:getHeight(),
            self.light_image:getWidth() / 2,
            self.light_image:getHeight() / 2
        )

        love.graphics.setColor(1, 1, 1, 1)

    elseif light.type == "spotlight" then
        -- TODO: Implement spotlight using image or shader
        dprint("WARNING: Spotlight not implemented yet")
    end
end

-- Get light count (for debugging)
function lighting:getCount()
    return #self.lights
end

-- Enable/disable entire lighting system
function lighting:setEnabled(enabled)
    self.enabled = enabled
end

-- Resize lighting canvas (call on window resize)
function lighting:resize(width, height)
    if self.canvas then
        self.canvas:release()
    end
    self.canvas = love.graphics.newCanvas(width, height)
end

-- Initialize on require
lighting:init()

return lighting

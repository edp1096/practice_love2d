-- engine/lighting/init.lua
-- Lighting system manager (ambient, point lights, spotlights)

local shaders = require "engine.lighting.shaders"
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
    shaders.init()

    -- Create canvas for lighting
    local width, height = love.graphics.getDimensions()
    self.canvas = love.graphics.newCanvas(width, height)

    dprint("Lighting system initialized")
end

-- Set ambient light color
function lighting:setAmbient(preset_or_color, g, b)
    if type(preset_or_color) == "string" then
        -- Use preset
        local preset = self.AMBIENT_PRESETS[preset_or_color]
        if preset then
            self.ambient_color = {preset[1], preset[2], preset[3]}
        else
            print("WARNING: Unknown ambient preset: " .. preset_or_color)
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

-- Draw lighting (call after camera:detach(), before screen:Attach())
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

    -- Get camera scale (default 1.0 if no camera)
    local scale = 1.0
    if camera and camera.scale then
        scale = camera.scale
    end

    -- Convert to screen coordinates for shader
    local screen_x, screen_y = world_x, world_y
    if camera then
        screen_x, screen_y = camera:cameraCoords(world_x, world_y)
    end

    -- Convert radius to screen space
    local screen_radius = light.radius * scale

    local intensity = light:getCurrentIntensity()

    if light.type == "point" then
        shaders.light:send("light_position", {screen_x, screen_y})
        shaders.light:send("light_radius", screen_radius)
        shaders.light:send("light_color", light.color)
        shaders.light:send("light_intensity", intensity)

        love.graphics.setShader(shaders.light)
        love.graphics.rectangle("fill",
            world_x - light.radius,
            world_y - light.radius,
            light.radius * 2,
            light.radius * 2
        )
        love.graphics.setShader()

    elseif light.type == "spotlight" then
        local dir_x = math.cos(light.angle)
        local dir_y = math.sin(light.angle)

        shaders.spotlight:send("light_position", {screen_x, screen_y})
        shaders.spotlight:send("light_direction", {dir_x, dir_y})
        shaders.spotlight:send("light_radius", screen_radius)
        shaders.spotlight:send("cone_angle", light.cone_angle)
        shaders.spotlight:send("light_color", light.color)
        shaders.spotlight:send("light_intensity", intensity)

        love.graphics.setShader(shaders.spotlight)
        love.graphics.rectangle("fill",
            world_x - light.radius,
            world_y - light.radius,
            light.radius * 2,
            light.radius * 2
        )
        love.graphics.setShader()
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
    dprint("Lighting canvas resized: " .. width .. "x" .. height)
end

-- Initialize on require
lighting:init()

return lighting

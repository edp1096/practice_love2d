-- engine/systems/weather/fog.lua
-- Fog/mist weather effect using soft gradient textures
-- Features: smooth edges, multi-layer scrolling, natural blending

local constants = require "engine.core.constants"

local fog = {}

-- Textures and layers
local fog_texture = nil        -- Soft gradient fog puff
local fog_texture_large = nil  -- Larger, softer fog
local layers = {}

-- Virtual screen size (from constants)
local VW, VH = constants.RENDER_WIDTH, constants.RENDER_HEIGHT

-- Configuration
local FOG_COLOR = {0.85, 0.88, 0.92}  -- Light gray-blue
local MIST_COLOR = {0.9, 0.92, 0.95}  -- Lighter for mist

-- Layer configuration
local LAYER_CONFIG = {
    -- Small, faster moving wisps (foreground)
    { count = 6, size_min = 80, size_max = 150, speed = 25, alpha = 0.08, texture = "small" },
    -- Medium fog patches
    { count = 8, size_min = 150, size_max = 280, speed = 15, alpha = 0.06, texture = "small" },
    -- Large, slow background fog
    { count = 5, size_min = 300, size_max = 500, speed = 8, alpha = 0.04, texture = "large" },
    -- Extra large atmospheric layer
    { count = 3, size_min = 450, size_max = 700, speed = 5, alpha = 0.03, texture = "large" },
}

-- Create soft gradient fog texture
local function createFogTexture(size, softness)
    local canvas = love.graphics.newCanvas(size, size)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    local center = size / 2
    local max_radius = center * softness

    -- Draw multiple concentric circles with decreasing alpha for smooth gradient
    local steps = 40
    for i = steps, 1, -1 do
        local ratio = i / steps
        local radius = max_radius * ratio
        local alpha = (1 - ratio) * 0.8  -- Fade from edge to center (inverted: center is more opaque)

        -- Use exponential falloff for more natural fog look
        alpha = alpha * alpha * 1.5

        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.circle("fill", center, center, radius, 64)
    end

    -- Add extra soft center
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.circle("fill", center, center, max_radius * 0.3, 32)

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)

    return canvas
end

-- Create noise-like fog texture (more irregular shape)
local function createNoisyFogTexture(size)
    local canvas = love.graphics.newCanvas(size, size)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    local center = size / 2

    -- Draw multiple offset circles for irregular shape
    local blobs = {
        { ox = 0, oy = 0, r = 0.45, a = 0.25 },
        { ox = -0.15, oy = -0.1, r = 0.35, a = 0.2 },
        { ox = 0.12, oy = 0.08, r = 0.38, a = 0.18 },
        { ox = -0.08, oy = 0.15, r = 0.32, a = 0.15 },
        { ox = 0.1, oy = -0.12, r = 0.3, a = 0.15 },
    }

    for _, blob in ipairs(blobs) do
        local bx = center + blob.ox * size
        local by = center + blob.oy * size
        local max_radius = blob.r * size

        -- Gradient for each blob
        local steps = 25
        for i = steps, 1, -1 do
            local ratio = i / steps
            local radius = max_radius * ratio
            local alpha = (1 - ratio) * blob.a
            alpha = alpha * alpha * 2  -- Exponential falloff

            love.graphics.setColor(1, 1, 1, alpha)
            love.graphics.circle("fill", bx, by, radius, 32)
        end
    end

    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1)

    return canvas
end

-- Layer class
local Layer = {}
Layer.__index = Layer

function Layer:new(x, y, size, speed_x, speed_y, alpha, texture)
    return setmetatable({
        x = x,
        y = y,
        size = size,
        speed_x = speed_x,
        speed_y = speed_y,
        alpha = alpha,
        texture = texture,
        rotation = math.random() * math.pi * 2,
        rotation_speed = (math.random() - 0.5) * 0.1,  -- Slow rotation
    }, Layer)
end

function Layer:update(dt)
    -- Move layer
    self.x = self.x + self.speed_x * dt
    self.y = self.y + self.speed_y * dt

    -- Slow rotation for organic movement
    self.rotation = self.rotation + self.rotation_speed * dt

    -- Wrap around screen
    local margin = self.size * 0.6
    if self.x > VW + margin then
        self.x = -margin
    elseif self.x < -margin then
        self.x = VW + margin
    end

    if self.y > VH + margin then
        self.y = -margin
    elseif self.y < -margin then
        self.y = VH + margin
    end
end

function Layer:draw(intensity, color)
    local tex = self.texture == "large" and fog_texture_large or fog_texture
    if not tex then return end

    local tex_size = tex:getWidth()
    local scale = self.size / tex_size
    local alpha = self.alpha * intensity

    love.graphics.setColor(color[1], color[2], color[3], alpha)
    love.graphics.draw(
        tex,
        self.x, self.y,
        self.rotation,
        scale, scale,
        tex_size / 2, tex_size / 2  -- Center origin
    )
end

-- Initialize fog effect
function fog:initialize(intensity)
    intensity = intensity or 1.0
    layers = {}

    -- Create textures if needed
    if not fog_texture then
        fog_texture = createNoisyFogTexture(256)
    end
    if not fog_texture_large then
        fog_texture_large = createFogTexture(256, 0.9)
    end

    -- Create layers based on configuration
    for _, config in ipairs(LAYER_CONFIG) do
        for i = 1, config.count do
            local x = math.random(0, VW)
            local y = math.random(0, VH)
            local size = math.random(config.size_min, config.size_max)

            -- Random drift direction
            local angle = math.random() * math.pi * 2
            local speed = config.speed * (0.7 + math.random() * 0.6)
            local speed_x = math.cos(angle) * speed
            local speed_y = math.sin(angle) * speed

            -- Vary alpha slightly
            local alpha = config.alpha * (0.8 + math.random() * 0.4)

            table.insert(layers, Layer:new(x, y, size, speed_x, speed_y, alpha, config.texture))
        end
    end

    -- Sort layers by size (larger = background)
    table.sort(layers, function(a, b) return a.size > b.size end)
end

-- Update
function fog:update(dt, intensity)
    for _, layer in ipairs(layers) do
        layer:update(dt)
    end
end

-- Draw
function fog:draw(intensity)
    if #layers == 0 then return end

    local display = require "engine.core.display"
    display:Attach()

    -- Use alpha blending for natural fog layering
    love.graphics.setBlendMode("alpha")

    -- Choose color based on intensity (mist = lighter, fog = denser)
    local color = intensity < 0.6 and MIST_COLOR or FOG_COLOR

    -- Draw all layers (sorted large to small)
    for _, layer in ipairs(layers) do
        layer:draw(intensity, color)
    end

    -- Reset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")

    display:Detach()
end

-- Cleanup
function fog:cleanup()
    layers = {}
    -- Don't destroy textures (reusable)
end

return fog

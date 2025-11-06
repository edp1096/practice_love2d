-- engine/lighting/light.lua
-- Individual light source object

local Light = {}
Light.__index = Light

-- Create a new light
function Light.new(config)
    local light = setmetatable({}, Light)

    -- Type: "point" or "spotlight"
    light.type = config.type or "point"

    -- Position (world coordinates)
    light.x = config.x or 0
    light.y = config.y or 0

    -- Light properties
    light.radius = config.radius or 100
    light.color = config.color or {1, 1, 1}  -- RGB (0-1)
    light.intensity = config.intensity or 1.0

    -- Spotlight specific
    light.angle = config.angle or 0  -- Direction in radians
    light.cone_angle = config.cone_angle or math.pi / 4  -- 45 degrees

    -- State
    light.enabled = true

    -- Flickering (optional)
    light.flicker = config.flicker or false
    light.flicker_speed = config.flicker_speed or 5.0
    light.flicker_amount = config.flicker_amount or 0.2
    light.flicker_time = 0

    return light
end

-- Update light (for flickering, animation, etc)
function Light:update(dt)
    if self.flicker then
        self.flicker_time = self.flicker_time + dt
    end
end

-- Get current intensity (with flicker applied)
function Light:getCurrentIntensity()
    if not self.flicker then
        return self.intensity
    end

    local flicker_value = math.sin(self.flicker_time * self.flicker_speed * math.pi)
    flicker_value = flicker_value * self.flicker_amount

    return self.intensity * (1.0 + flicker_value)
end

-- Set position
function Light:setPosition(x, y)
    self.x = x
    self.y = y
end

-- Set angle (spotlight only)
function Light:setAngle(angle)
    self.angle = angle
end

-- Set color
function Light:setColor(r, g, b)
    self.color = {r, g, b}
end

-- Set intensity
function Light:setIntensity(intensity)
    self.intensity = intensity
end

-- Enable/disable
function Light:setEnabled(enabled)
    self.enabled = enabled
end

return Light

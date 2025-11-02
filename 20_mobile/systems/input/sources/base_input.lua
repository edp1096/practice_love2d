-- systems/input/sources/base_input.lua
-- Base interface for all input sources
-- All input sources should implement these methods

local base_input = {}
base_input.__index = base_input

-- Create a new input source
function base_input:new()
    local instance = setmetatable({}, self)
    instance.enabled = true
    instance.priority = 0 -- Higher priority sources are checked first
    instance.name = "BaseInput"
    return instance
end

-- Check if this input source is available
function base_input:isAvailable()
    return false
end

-- Get movement vector (-1 to 1 for each axis)
-- Returns: vx, vy, has_input
function base_input:getMovement()
    return 0, 0, false
end

-- Get aim direction angle (in radians)
-- Returns: angle, has_aim
function base_input:getAimDirection(player_x, player_y, cam)
    return 0, false
end

-- Check if action button is down
function base_input:isActionDown(action)
    return false
end

-- Check if action was just pressed
function base_input:wasActionPressed(action, source, value)
    return false
end

-- Update input source (called each frame)
function base_input:update(dt)
    -- Override in subclasses
end

-- Enable/disable this input source
function base_input:setEnabled(enabled)
    self.enabled = enabled
end

-- Get debug information
function base_input:getDebugInfo()
    return self.name .. ": " .. (self.enabled and "Enabled" or "Disabled")
end

return base_input

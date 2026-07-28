-- engine/utils/convert.lua
-- Type conversion utilities for LÖVE 12.0 / Lua 5.4 compatibility
-- Handles safe conversion between string/number/boolean types

local convert = {}

-- LÖVE 12.0 / Lua 5.4: Safe number conversion
-- Converts string/number to number, returns default if conversion fails
-- @param value: Value to convert (any type)
-- @param default: Default value if conversion fails (optional, defaults to 0)
-- @return number
function convert:toNumber(value, default)
    if type(value) == "number" then
        return value
    end
    local num = tonumber(value)
    return num or default or 0
end

-- Safe integer conversion (for indices, monitor numbers, counts, etc.)
-- Floors the result to ensure integer value
-- @param value: Value to convert (any type)
-- @param default: Default value if conversion fails (optional, defaults to 0)
-- @return integer (floored number)
function convert:toInt(value, default)
    local num = self:toNumber(value, default)
    return math.floor(num)
end

-- Safe boolean conversion
-- Handles Lua boolean, string "true"/"false", and numeric 0/1
-- @param value: Value to convert (any type)
-- @param default: Default value if conversion fails (optional, defaults to false)
-- @return boolean
function convert:toBool(value, default)
    if type(value) == "boolean" then
        return value
    end
    if value == "true" or value == 1 then
        return true
    elseif value == "false" or value == 0 then
        return false
    end
    return default or false
end

-- String to number with range clamping
-- Useful for volume levels, percentages, indices with bounds
-- @param value: Value to convert (any type)
-- @param min: Minimum allowed value (optional)
-- @param max: Maximum allowed value (optional)
-- @param default: Default value if conversion fails (optional, defaults to 0)
-- @return number (clamped to [min, max])
function convert:toNumberClamped(value, min, max, default)
    local num = self:toNumber(value, default)
    if min and num < min then return min end
    if max and num > max then return max end
    return num
end

-- Safe percentage conversion (0.0 ~ 1.0)
-- Converts string/number to normalized percentage
-- @param value: Value to convert (any type)
-- @param default: Default value if conversion fails (optional, defaults to 1.0)
-- @return number (clamped to [0.0, 1.0])
function convert:toPercent(value, default)
    return self:toNumberClamped(value, 0.0, 1.0, default or 1.0)
end

return convert

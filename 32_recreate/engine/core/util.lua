local util = {}

function util.clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function util.countdown(value, dt)
    local remaining = math.max(0, value - dt)
    if remaining < 1e-9 then return 0 end
    return remaining
end

function util.sign(value)
    if value < 0 then return -1 end
    if value > 0 then return 1 end
    return 0
end

function util.length(x, y)
    return math.sqrt(x * x + y * y)
end

function util.normalize(x, y)
    local length = util.length(x, y)
    if length == 0 then return 0, 0 end
    return x / length, y / length
end

function util.sortedKeys(value)
    local keys = {}
    for key in pairs(value or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

function util.deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end

    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[util.deepCopy(key, seen)] = util.deepCopy(item, seen)
    end
    return copy
end

function util.merge(base, override)
    local result = util.deepCopy(base or {})
    for key, value in pairs(override or {}) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = util.merge(result[key], value)
        else
            result[key] = util.deepCopy(value)
        end
    end
    return result
end

function util.arrayContains(values, expected)
    for _, value in ipairs(values or {}) do
        if value == expected then return true end
    end
    return false
end

return util

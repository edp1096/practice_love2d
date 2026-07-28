local Schema = {}

local function location(path)
    return path or "data"
end

function Schema.object(value, path, allowed, required)
    path = location(path)
    if type(value) ~= "table" then
        return nil, path .. " must be a table"
    end
    local known = {}
    for _, name in ipairs(allowed or {}) do known[name] = true end
    for key in pairs(value) do
        if type(key) ~= "string" or not known[key] then
            return nil, path .. " contains unknown field '" ..
                tostring(key) .. "'"
        end
    end
    for _, name in ipairs(required or {}) do
        if value[name] == nil then
            return nil, path .. "." .. name .. " is required"
        end
    end
    return true
end

function Schema.map(value, path, validate_value)
    path = location(path)
    if type(value) ~= "table" then
        return nil, path .. " must be a table"
    end
    for key, item in pairs(value) do
        if type(key) ~= "string" or key == "" then
            return nil, path .. " keys must be non-empty strings"
        end
        local valid, value_error =
            validate_value(item, path .. "." .. key, key)
        if not valid then return nil, value_error end
    end
    return true
end

function Schema.string(value, path)
    if type(value) ~= "string" or value == "" then
        return nil, location(path) .. " must be a non-empty string"
    end
    return true
end

function Schema.optionalString(value, path)
    if value == nil then return true end
    return Schema.string(value, path)
end

function Schema.nonNegativeInteger(value, path)
    if type(value) ~= "number" or
       value < 0 or value % 1 ~= 0 then
        return nil, location(path) ..
            " must be a non-negative integer"
    end
    return true
end

function Schema.positiveInteger(value, path)
    if type(value) ~= "number" or
       value < 1 or value % 1 ~= 0 then
        return nil, location(path) .. " must be a positive integer"
    end
    return true
end

function Schema.enum(value, path, values)
    for _, expected in ipairs(values) do
        if value == expected then return true end
    end
    return nil, location(path) .. " has unsupported value '" ..
        tostring(value) .. "'"
end

return Schema

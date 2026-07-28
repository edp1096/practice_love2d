local Serializer = {}

local function finiteNumber(value)
    return value == value and
        value ~= math.huge and value ~= -math.huge
end

local function classifyTable(value, path)
    if getmetatable(value) ~= nil then
        return nil, path .. " must not have a metatable"
    end
    local strings = {}
    local integer_count = 0
    local maximum = 0
    for key in pairs(value) do
        if type(key) == "string" then
            strings[#strings + 1] = key
        elseif type(key) == "number" and
               finiteNumber(key) and key >= 1 and
               key % 1 == 0 then
            integer_count = integer_count + 1
            maximum = math.max(maximum, key)
        else
            return nil, path ..
                " keys must be strings or positive array indexes"
        end
    end
    if #strings > 0 and integer_count > 0 then
        return nil, path .. " must not mix map and array keys"
    end
    if integer_count > 0 and maximum ~= integer_count then
        return nil, path .. " array indexes must be consecutive"
    end
    table.sort(strings)
    return {
        array_length = integer_count,
        string_keys = strings,
    }
end

local function walk(value, path, seen, emit)
    local value_type = type(value)
    if value_type == "nil" then
        return emit and "nil" or true
    elseif value_type == "boolean" then
        return emit and tostring(value) or true
    elseif value_type == "number" then
        if not finiteNumber(value) then
            return nil, path .. " must be a finite number"
        end
        return emit and string.format("%.17g", value) or true
    elseif value_type == "string" then
        return emit and string.format("%q", value) or true
    elseif value_type ~= "table" then
        return nil, path .. " contains unsupported " .. value_type
    end

    if seen[value] then
        return nil, path .. " contains a cycle or repeated table reference"
    end
    seen[value] = true
    local shape, shape_error = classifyTable(value, path)
    if not shape then return nil, shape_error end

    local parts = emit and {"{"} or nil
    if shape.array_length > 0 then
        for index = 1, shape.array_length do
            local encoded, encode_error = walk(
                value[index],
                string.format("%s[%d]", path, index),
                seen,
                emit
            )
            if not encoded then return nil, encode_error end
            if emit then
                if index > 1 then parts[#parts + 1] = "," end
                parts[#parts + 1] = encoded
            end
        end
    else
        for index, key in ipairs(shape.string_keys) do
            local encoded, encode_error = walk(
                value[key],
                path .. "." .. key,
                seen,
                emit
            )
            if not encoded then return nil, encode_error end
            if emit then
                if index > 1 then parts[#parts + 1] = "," end
                parts[#parts + 1] =
                    "[" .. string.format("%q", key) .. "]=" .. encoded
            end
        end
    end
    if emit then
        parts[#parts + 1] = "}"
        return table.concat(parts)
    end
    return true
end

function Serializer.validate(value)
    return walk(value, "value", {}, false)
end

function Serializer.encode(value)
    local encoded, encode_error = walk(value, "value", {}, true)
    if not encoded then return nil, encode_error end
    return "return " .. encoded .. "\n"
end

return Serializer

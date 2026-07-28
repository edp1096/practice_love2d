-- Deterministic JSON encoder plus flat primitive request parsing.
-- The debug protocol never evaluates arbitrary Lua or accepts nested commands.

local json = {}

local function escape(value)
    return value:gsub('[%z\1-\31\\"]', function(char)
        local escapes = {
            ['"'] = '\\"',
            ['\\'] = '\\\\',
            ['\b'] = '\\b',
            ['\f'] = '\\f',
            ['\n'] = '\\n',
            ['\r'] = '\\r',
            ['\t'] = '\\t',
        }
        return escapes[char] or string.format("\\u%04x", char:byte())
    end)
end

local function arraySize(value)
    local maximum = 0
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return nil
        end
        maximum = math.max(maximum, key)
        count = count + 1
    end
    if count ~= maximum then return nil end
    return maximum
end

local function encode(value, seen)
    local value_type = type(value)
    if value_type == "nil" then
        return "null"
    elseif value_type == "boolean" then
        return value and "true" or "false"
    elseif value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    elseif value_type == "string" then
        return '"' .. escape(value) .. '"'
    elseif value_type ~= "table" then
        return '"' .. escape(tostring(value)) .. '"'
    end

    seen = seen or {}
    if seen[value] then return '"<cycle>"' end
    seen[value] = true

    local size = arraySize(value)
    local parts = {}
    if size then
        for index = 1, size do
            parts[#parts + 1] = encode(value[index], seen)
        end
        seen[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local entries = {}
    for key, item in pairs(value) do
        entries[#entries + 1] = {key = tostring(key), value = item}
    end
    table.sort(entries, function(left, right)
        return left.key < right.key
    end)
    for _, entry in ipairs(entries) do
        parts[#parts + 1] =
            '"' .. escape(entry.key) .. '":' ..
            encode(entry.value, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function decodeString(value)
    return value:gsub("\\u(%x%x%x%x)", function(hex)
        local code = tonumber(hex, 16)
        return code and code < 128 and string.char(code) or "?"
    end):gsub("\\(.)", function(char)
        local escapes = {
            ['"'] = '"',
            ['\\'] = '\\',
            ['/'] = '/',
            b = '\b',
            f = '\f',
            n = '\n',
            r = '\r',
            t = '\t',
        }
        return escapes[char] or char
    end)
end

function json.encode(value)
    return encode(value)
end

function json.getString(line, name)
    local position = line:match('"' .. name .. '"%s*:%s*"()')
    if not position then return nil end
    local escaped = false
    for index = position, #line do
        local char = line:sub(index, index)
        if char == '"' and not escaped then
            return decodeString(line:sub(position, index - 1))
        end
        if char == "\\" and not escaped then
            escaped = true
        else
            escaped = false
        end
    end
    return nil
end

function json.getNumber(line, name)
    local position = line:match('"' .. name .. '"%s*:%s*()')
    if not position then return nil end
    local token = line:sub(position):match("^([^,%}%]%s]+)")
    return tonumber(token)
end

function json.getBoolean(line, name)
    local position = line:match('"' .. name .. '"%s*:%s*()')
    if not position then return nil end
    local value = line:sub(position)
    if value:match("^true") then return true end
    if value:match("^false") then return false end
    return nil
end

return json

-- Deterministic JSON encoder and a bounded, non-evaluating JSON decoder.

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

function json.encode(value)
    return encode(value)
end

local function utf8(codepoint)
    if codepoint <= 0x7f then
        return string.char(codepoint)
    elseif codepoint <= 0x7ff then
        return string.char(
            0xc0 + math.floor(codepoint / 0x40),
            0x80 + codepoint % 0x40
        )
    elseif codepoint <= 0xffff then
        return string.char(
            0xe0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    elseif codepoint <= 0x10ffff then
        return string.char(
            0xf0 + math.floor(codepoint / 0x40000),
            0x80 + math.floor(codepoint / 0x1000) % 0x40,
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    end
    return nil
end

local function decoder(source)
    local position = 1
    local length = #source

    local function fail(message)
        return nil, string.format(
            "JSON byte %d: %s",
            position,
            message
        )
    end

    local function skipWhitespace()
        local _, last = source:find("^[ \t\r\n]*", position)
        position = (last or position - 1) + 1
    end

    local parseValue

    local function parseString()
        if source:sub(position, position) ~= '"' then
            return fail("expected string")
        end
        position = position + 1
        local parts = {}
        local start = position
        while position <= length do
            local byte = source:byte(position)
            if byte == 34 then
                parts[#parts + 1] =
                    source:sub(start, position - 1)
                position = position + 1
                return table.concat(parts)
            elseif byte == 92 then
                parts[#parts + 1] =
                    source:sub(start, position - 1)
                position = position + 1
                local escaped = source:sub(position, position)
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
                if escapes[escaped] then
                    parts[#parts + 1] = escapes[escaped]
                    position = position + 1
                elseif escaped == "u" then
                    local hex = source:sub(
                        position + 1,
                        position + 4
                    )
                    if not hex:match("^%x%x%x%x$") then
                        return fail("invalid Unicode escape")
                    end
                    local codepoint = tonumber(hex, 16)
                    position = position + 5
                    if codepoint >= 0xd800 and codepoint <= 0xdbff then
                        if source:sub(position, position + 1) ~=
                           "\\u" then
                            return fail(
                                "high surrogate requires low surrogate"
                            )
                        end
                        local low_hex =
                            source:sub(position + 2, position + 5)
                        local low = tonumber(low_hex, 16)
                        if not low or low < 0xdc00 or low > 0xdfff then
                            return fail("invalid low surrogate")
                        end
                        codepoint = 0x10000 +
                            (codepoint - 0xd800) * 0x400 +
                            (low - 0xdc00)
                        position = position + 6
                    elseif codepoint >= 0xdc00 and
                           codepoint <= 0xdfff then
                        return fail("unexpected low surrogate")
                    end
                    local encoded = utf8(codepoint)
                    if not encoded then
                        return fail("invalid Unicode codepoint")
                    end
                    parts[#parts + 1] = encoded
                else
                    return fail("invalid string escape")
                end
                start = position
            elseif byte < 32 then
                return fail("unescaped control character")
            else
                position = position + 1
            end
        end
        return fail("unterminated string")
    end

    local function parseNumber()
        local start = position
        if source:sub(position, position) == "-" then
            position = position + 1
        end

        local first = source:sub(position, position)
        if first == "0" then
            position = position + 1
            if source:sub(position, position):match("%d") then
                position = start
                return fail("leading zero is not allowed")
            end
        elseif first:match("[1-9]") then
            repeat
                position = position + 1
            until not source:sub(position, position):match("%d")
        else
            position = start
            return fail("invalid number")
        end

        if source:sub(position, position) == "." then
            position = position + 1
            if not source:sub(position, position):match("%d") then
                position = start
                return fail("fraction requires a digit")
            end
            repeat
                position = position + 1
            until not source:sub(position, position):match("%d")
        end

        local exponent = source:sub(position, position)
        if exponent == "e" or exponent == "E" then
            position = position + 1
            local sign = source:sub(position, position)
            if sign == "+" or sign == "-" then
                position = position + 1
            end
            if not source:sub(position, position):match("%d") then
                position = start
                return fail("exponent requires a digit")
            end
            repeat
                position = position + 1
            until not source:sub(position, position):match("%d")
        end

        local token = source:sub(start, position - 1)
        local value = tonumber(token)
        if not value or value ~= value or
           value == math.huge or value == -math.huge then
            position = start
            return fail("number is not finite")
        end
        return value
    end

    local function parseArray(depth)
        position = position + 1
        skipWhitespace()
        local result = {}
        if source:sub(position, position) == "]" then
            position = position + 1
            return result
        end
        while true do
            local value, value_error = parseValue(depth + 1)
            if value_error then return nil, value_error end
            result[#result + 1] = value
            skipWhitespace()
            local delimiter = source:sub(position, position)
            if delimiter == "]" then
                position = position + 1
                return result
            elseif delimiter ~= "," then
                return fail("expected ',' or ']'")
            end
            position = position + 1
            skipWhitespace()
        end
    end

    local function parseObject(depth)
        position = position + 1
        skipWhitespace()
        local result = {}
        if source:sub(position, position) == "}" then
            position = position + 1
            return result
        end
        while true do
            local key, key_error = parseString()
            if key_error then return nil, key_error end
            if result[key] ~= nil then
                return fail("duplicate object key '" .. key .. "'")
            end
            skipWhitespace()
            if source:sub(position, position) ~= ":" then
                return fail("expected ':'")
            end
            position = position + 1
            skipWhitespace()
            local value, value_error = parseValue(depth + 1)
            if value_error then return nil, value_error end
            result[key] = value
            skipWhitespace()
            local delimiter = source:sub(position, position)
            if delimiter == "}" then
                position = position + 1
                return result
            elseif delimiter ~= "," then
                return fail("expected ',' or '}'")
            end
            position = position + 1
            skipWhitespace()
        end
    end

    parseValue = function(depth)
        if depth > 64 then return fail("nesting exceeds 64 levels") end
        skipWhitespace()
        local character = source:sub(position, position)
        if character == '"' then
            return parseString()
        elseif character == "{" then
            return parseObject(depth)
        elseif character == "[" then
            return parseArray(depth)
        elseif character == "-" or character:match("%d") then
            return parseNumber()
        elseif source:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        elseif source:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        elseif source:sub(position, position + 3) == "null" then
            position = position + 4
            return json.null
        end
        return fail("expected value")
    end

    local result, parse_error = parseValue(0)
    if parse_error then return nil, parse_error end
    skipWhitespace()
    if position <= length then
        return fail("unexpected trailing data")
    end
    return result
end

json.null = {}

function json.decode(source)
    if type(source) ~= "string" then
        return nil, "JSON source must be a string"
    end
    return decoder(source)
end

local function object(value)
    if type(value) == "string" then
        value = json.decode(value)
    end
    if type(value) ~= "table" then return nil end
    return value
end

function json.getString(value, name)
    value = object(value)
    local result = value and value[name]
    return type(result) == "string" and result or nil
end

function json.getNumber(value, name)
    value = object(value)
    local result = value and value[name]
    return type(result) == "number" and result or nil
end

function json.getBoolean(value, name)
    value = object(value)
    local result = value and value[name]
    return type(result) == "boolean" and result or nil
end

return json

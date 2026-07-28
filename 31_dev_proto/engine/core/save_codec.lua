-- Safe, deterministic codec for save files.
-- Reads the table syntax emitted by older versions without executing Lua code.

local codec = {}

codec.MAX_INPUT_SIZE = 4 * 1024 * 1024
codec.MAX_DEPTH = 128

local key_type_order = {
    number = 1,
    string = 2,
    boolean = 3,
}

local function quote_string(value)
    return string.format("%q", value)
end

local function is_dense_array(value)
    local count = 0
    local largest = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false, 0
        end
        count = count + 1
        largest = math.max(largest, key)
    end
    return count == largest, largest
end

local function sorted_keys(value)
    local keys = {}
    for key in pairs(value) do
        local key_type = type(key)
        if not key_type_order[key_type] then
            return nil, "unsupported table key type: " .. key_type
        end
        if key_type == "number" and
           (key ~= key or key == math.huge or key == -math.huge) then
            return nil, "non-finite table keys are not supported"
        end
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        local left_type = type(left)
        local right_type = type(right)
        if left_type ~= right_type then
            return key_type_order[left_type] < key_type_order[right_type]
        end
        if left_type == "boolean" then
            return left == false and right == true
        end
        return left < right
    end)
    return keys
end

local function encode_value(value, indent, seen, depth)
    if depth > codec.MAX_DEPTH then
        return nil, "save data exceeds maximum nesting depth"
    end

    local value_type = type(value)
    if value_type == "nil" then
        return "nil"
    elseif value_type == "string" then
        return quote_string(value)
    elseif value_type == "boolean" then
        return tostring(value)
    elseif value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "non-finite numbers are not supported"
        end
        return tostring(value)
    elseif value_type ~= "table" then
        return nil, "unsupported save value type: " .. value_type
    end

    if seen[value] then
        return nil, "cyclic tables cannot be saved"
    end
    seen[value] = true

    local next_indent = indent .. "  "
    local fields = {}
    local dense, size = is_dense_array(value)
    if dense then
        for index = 1, size do
            local encoded, err =
                encode_value(value[index], next_indent, seen, depth + 1)
            if not encoded then
                seen[value] = nil
                return nil, err
            end
            fields[#fields + 1] = next_indent .. encoded
        end
    else
        local keys, key_error = sorted_keys(value)
        if not keys then
            seen[value] = nil
            return nil, key_error
        end
        for _, key in ipairs(keys) do
            local encoded_key, key_err =
                encode_value(key, next_indent, seen, depth + 1)
            if not encoded_key then
                seen[value] = nil
                return nil, key_err
            end
            local encoded_value, value_err =
                encode_value(value[key], next_indent, seen, depth + 1)
            if not encoded_value then
                seen[value] = nil
                return nil, value_err
            end
            fields[#fields + 1] = string.format(
                "%s[%s] = %s",
                next_indent,
                encoded_key,
                encoded_value
            )
        end
    end

    seen[value] = nil
    if #fields == 0 then
        return "{}"
    end
    return "{\n" .. table.concat(fields, ",\n") .. "\n" .. indent .. "}"
end

function codec.encode(value)
    return encode_value(value, "", {}, 0)
end

local Parser = {}
Parser.__index = Parser

function Parser:new(input)
    return setmetatable({
        input = input,
        length = #input,
        position = 1,
    }, self)
end

function Parser:error(message)
    return nil, string.format("%s at byte %d", message, self.position)
end

function Parser:skip_space()
    local whitespace = self.input:sub(self.position):match("^[ \t\r\n]*")
    self.position = self.position + #whitespace
end

function Parser:consume(character)
    self:skip_space()
    if self.input:sub(self.position, self.position) ~= character then
        return false
    end
    self.position = self.position + 1
    return true
end

function Parser:word(word)
    self:skip_space()
    if self.input:sub(self.position, self.position + #word - 1) ~= word then
        return false
    end
    local following = self.input:sub(
        self.position + #word,
        self.position + #word
    )
    if following:match("[%w_]") then
        return false
    end
    self.position = self.position + #word
    return true
end

local escaped_characters = {
    a = "\a",
    b = "\b",
    f = "\f",
    n = "\n",
    r = "\r",
    t = "\t",
    v = "\v",
    ["\\"] = "\\",
    ['"'] = '"',
    ["'"] = "'",
}

function Parser:parse_string()
    self:skip_space()
    local quote = self.input:sub(self.position, self.position)
    if quote ~= '"' and quote ~= "'" then
        return self:error("expected string")
    end
    self.position = self.position + 1
    local result = {}

    while self.position <= self.length do
        local character = self.input:sub(self.position, self.position)
        self.position = self.position + 1
        if character == quote then
            return table.concat(result)
        elseif character == "\\" then
            if self.position > self.length then
                return self:error("unfinished string escape")
            end
            local escaped = self.input:sub(self.position, self.position)
            self.position = self.position + 1
            if escaped:match("%d") then
                local digits = escaped
                for _ = 1, 2 do
                    local digit = self.input:sub(
                        self.position,
                        self.position
                    )
                    if not digit:match("%d") then break end
                    digits = digits .. digit
                    self.position = self.position + 1
                end
                local byte = tonumber(digits)
                if byte > 255 then
                    return self:error("decimal escape exceeds 255")
                end
                result[#result + 1] = string.char(byte)
            elseif escaped == "\n" then
                result[#result + 1] = "\n"
            elseif escaped == "\r" then
                if self.input:sub(self.position, self.position) == "\n" then
                    self.position = self.position + 1
                end
                result[#result + 1] = "\n"
            elseif escaped_characters[escaped] then
                result[#result + 1] = escaped_characters[escaped]
            else
                return self:error("unsupported string escape")
            end
        elseif character == "\n" or character == "\r" then
            return self:error("unescaped newline in string")
        else
            result[#result + 1] = character
        end
    end
    return self:error("unterminated string")
end

function Parser:parse_number()
    self:skip_space()
    local remaining = self.input:sub(self.position)
    local token =
        remaining:match("^[-+]?%d+%.?%d*[eE][-+]?%d+") or
        remaining:match("^[-+]?%.%d+[eE][-+]?%d+") or
        remaining:match("^[-+]?%d+%.?%d*") or
        remaining:match("^[-+]?%.%d+")
    if not token or token == "" or token == "+" or token == "-" then
        return self:error("expected number")
    end
    local value = tonumber(token)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return self:error("invalid number")
    end
    self.position = self.position + #token
    return value
end

function Parser:parse_table(depth)
    if depth > codec.MAX_DEPTH then
        return self:error("save data exceeds maximum nesting depth")
    end
    if not self:consume("{") then
        return self:error("expected table")
    end

    local result = {}
    local array_index = 1
    self:skip_space()
    if self:consume("}") then
        return result
    end

    while true do
        self:skip_space()
        if self:consume("[") then
            local key, key_error = self:parse_value(depth + 1)
            if key_error then return nil, key_error end
            if key == nil then
                return self:error("nil table key")
            end
            local key_type = type(key)
            if key_type ~= "number" and key_type ~= "string" and
               key_type ~= "boolean" then
                return self:error("unsupported table key type")
            end
            if not self:consume("]") then
                return self:error("expected ']'")
            end
            if not self:consume("=") then
                return self:error("expected '='")
            end
            local value, value_error = self:parse_value(depth + 1)
            if value_error then return nil, value_error end
            result[key] = value
        else
            local value, value_error = self:parse_value(depth + 1)
            if value_error then return nil, value_error end
            result[array_index] = value
            array_index = array_index + 1
        end

        self:skip_space()
        if self:consume("}") then
            break
        end
        if not self:consume(",") and not self:consume(";") then
            return self:error("expected ',', ';', or '}'")
        end
        self:skip_space()
        if self:consume("}") then
            break
        end
    end
    return result
end

function Parser:parse_value(depth)
    self:skip_space()
    local character = self.input:sub(self.position, self.position)
    if character == "{" then
        return self:parse_table(depth)
    elseif character == '"' or character == "'" then
        return self:parse_string()
    elseif character:match("[-+.%d]") then
        return self:parse_number()
    elseif self:word("true") then
        return true
    elseif self:word("false") then
        return false
    elseif self:word("nil") then
        return nil
    end
    return self:error("expected a save value")
end

function codec.decode(input)
    if type(input) ~= "string" then
        return nil, "save data must be a string"
    end
    if #input == 0 then
        return nil, "save data is empty"
    end
    if #input > codec.MAX_INPUT_SIZE then
        return nil, "save data exceeds maximum size"
    end

    local parser = Parser:new(input)
    parser:skip_space()
    parser:word("return")
    local value, err = parser:parse_value(0)
    if err then return nil, err end
    parser:skip_space()
    if parser.position <= parser.length then
        return parser:error("unexpected trailing data")
    end
    return value
end

return codec

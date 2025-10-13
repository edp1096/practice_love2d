local text = {}

-- Trim whitespace from both ends of string
function text:TrimSpace(s)
    -- if not s then return nil end
    return s:match("^%s*(.-)%s*$")
end

-- Split string by separator
function text:Split(str, sep)
    if not str then return {} end
    if not sep then sep = "%s" end -- Default to whitespace

    local result = {}
    local pattern

    -- Special handling for whitespace separators
    if sep == " " or sep == "%s" then
        -- Handle multiple consecutive spaces as single separator
        pattern = "([^%s]+)"
        for part in string.gmatch(str, pattern) do
            table.insert(result, part)
        end
    else
        -- Handle other separators (escape special pattern characters)
        local escaped_sep = sep:gsub("([%.%+%-%*%?%[%]%(%)%^%$%%])", "%%%1")
        pattern = "([^" .. escaped_sep .. "]+)"
        for part in string.gmatch(str, pattern) do
            table.insert(result, part)
        end
    end

    return result
end

-- Get first part before separator eg. _ - /
function text:GetFirstPart(str, sep)
    if not str then return nil end
    if not sep then sep = "_" end

    local parts = self:Split(str, sep)
    return parts[1]
end

-- Additional utility: Join array with separator
function text:Join(array, sep)
    if not array then return "" end
    if not sep then sep = " " end
    return table.concat(array, sep)
end

return text

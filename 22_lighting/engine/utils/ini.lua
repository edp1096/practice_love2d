--[[
Example:
    [section]
    key1 = value1

    [section2]
    key2 = value2

Code example:
    local config, err = ini:Read("config.ini")
    if err then
        print(err)
    else
        print(config.section.key1)
        print(config.section2.key2)
    end
 ]]

local convert = require "engine.utils.convert"

local ini = {}

function ini:Read(filename)
    local file = io.open(filename, "r")
    if not file then
        return nil, "Cannot open file: " .. filename
    end
    file:close()

    local config = {}
    local current_section = nil

    for line in io.lines(filename) do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^;") and not line:match("^#") then
            local section = line:match("^%[([^%]]+)%]$")
            if section then
                current_section = section
                config[current_section] = {}
            else
                local key, value = line:match("^(.-)=(.*)$")
                if key and value then
                    key = key:match("^%s*(.-)%s*$")
                    value = value:match("^%s*(.-)%s*$")

                    -- Try number first, then boolean, then keep as string
                    local num_value = tonumber(value)
                    if num_value then
                        value = num_value
                    elseif value == "true" or value == "false" then
                        value = convert:toBool(value)
                    end
                    -- Otherwise keep as string

                    if current_section then
                        config[current_section][key] = value
                    else
                        config[key] = value
                    end
                end
            end
        end
    end

    return config, nil
end

return ini

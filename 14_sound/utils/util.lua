local utils = {}

function utils:DeepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) == "table" then
                self:DeepMerge(target[k], v)
            else
                target[k] = v
            end
        else
            target[k] = v
        end
    end

    return target
end

function utils:DeepCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end

    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res

    for k, v in pairs(obj) do
        res[self:DeepCopy(k, s)] = self:DeepCopy(v, s)
    end

    return res
end

function utils:SaveConfig(GameConfig)
    -- Don't save on mobile platforms
    local os_name = love.system.getOS()
    if os_name == "Android" or os_name == "iOS" then
        return false
    end

    local success, err = pcall(function()
        local file = io.open("config.ini", "w")
        if file then
            file:write("Title = " .. GameConfig.title .. "\n")
            file:write("Author = " .. GameConfig.author .. "\n")
            file:write("\n")
            file:write("[Window]\n")
            file:write("Width = " .. GameConfig.width .. "\n")
            file:write("Height = " .. GameConfig.height .. "\n")
            file:write("FullScreen = " .. tostring(GameConfig.fullscreen) .. "\n")
            file:write("Monitor = " .. tostring(GameConfig.monitor) .. "\n")
            file:close()
            return true
        end
        return false
    end)

    if not success then
        print("Warning: Could not save config: " .. tostring(err))
        return false
    end

    return true
end

function utils:ReadOrCreateConfig()
    -- Don't try on mobile platforms
    local os_name = love.system.getOS()
    if os_name == "Android" or os_name == "iOS" then
        return false
    end

    local success, err = pcall(function()
        local file = io.open("config.ini", "r")
        if file then
            file:close()
            return true
        else
            local data = love.filesystem.read("config.ini")
            if data then
                local f = io.open("config.ini", "w")
                if f then
                    f:write(data)
                    f:close()
                    return true
                end
            end
        end
        return false
    end)

    if not success then
        print("Warning: Could not read/create config: " .. tostring(err))
        return false
    end

    return true
end

return utils

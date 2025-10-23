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

function utils:SaveConfig(GameConfig, sound_settings)
    local os_name = love.system.getOS()
    local is_mobile = (os_name == "Android" or os_name == "iOS")

    if is_mobile then
        -- Mobile: save using love.filesystem (Lua format)
        local success, err = pcall(function()
            local config_str = "return {\n"
            config_str = config_str .. "  title = \"" .. GameConfig.title .. "\",\n"
            config_str = config_str .. "  author = \"" .. GameConfig.author .. "\",\n"
            config_str = config_str .. "  width = " .. GameConfig.width .. ",\n"
            config_str = config_str .. "  height = " .. GameConfig.height .. ",\n"
            config_str = config_str .. "  fullscreen = " .. tostring(GameConfig.fullscreen) .. ",\n"

            if sound_settings then
                config_str = config_str .. "  sound = {\n"
                config_str = config_str .. "    master_volume = " .. tostring(sound_settings.master_volume) .. ",\n"
                config_str = config_str .. "    bgm_volume = " .. tostring(sound_settings.bgm_volume) .. ",\n"
                config_str = config_str .. "    sfx_volume = " .. tostring(sound_settings.sfx_volume) .. ",\n"
                config_str = config_str .. "    muted = " .. tostring(sound_settings.muted) .. "\n"
                config_str = config_str .. "  }\n"
            end

            config_str = config_str .. "}\n"

            return love.filesystem.write("mobile_config.lua", config_str)
        end)

        if not success then
            print("Warning: Could not save mobile config: " .. tostring(err))
            return false
        end
        return true
    end

    -- Desktop: save to config.ini
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

            -- Write Sound settings if provided
            if sound_settings then
                file:write("\n")
                file:write("[Sound]\n")
                file:write("MasterVolume = " .. tostring(sound_settings.master_volume) .. "\n")
                file:write("BGMVolume = " .. tostring(sound_settings.bgm_volume) .. "\n")
                file:write("SFXVolume = " .. tostring(sound_settings.sfx_volume) .. "\n")
                file:write("Muted = " .. tostring(sound_settings.muted) .. "\n")
            end

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

function utils:Get16by9Size(w, h)
    local target_aspect = 16 / 9
    local current_aspect = w / h

    if current_aspect > target_aspect then
        -- Screen is wider than 16:9 (e.g., 21:9) - constrain width
        return h * target_aspect, h
    else
        -- Screen is narrower than 16:9 (e.g., 16:10) - constrain height
        return w, w / target_aspect
    end
end

return utils

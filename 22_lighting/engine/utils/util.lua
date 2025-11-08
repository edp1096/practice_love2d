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

function utils:SaveConfig(GameConfig, sound_settings, input_settings, resolution_override)
    local os_name = love.system.getOS()
    local is_mobile = (os_name == "Android" or os_name == "iOS")

    if is_mobile then
        -- Mobile: save using love.filesystem (Lua format)
        local success, err = pcall(function()
            local config_str = "return {\n"

            if sound_settings then
                config_str = config_str .. "  sound = {\n"
                config_str = config_str .. "    master_volume = " .. tostring(sound_settings.master_volume) .. ",\n"
                config_str = config_str .. "    bgm_volume = " .. tostring(sound_settings.bgm_volume) .. ",\n"
                config_str = config_str .. "    sfx_volume = " .. tostring(sound_settings.sfx_volume) .. ",\n"
                config_str = config_str .. "    muted = " .. tostring(sound_settings.muted) .. "\n"
                config_str = config_str .. "  },\n"
            end

            if input_settings then
                config_str = config_str .. "  input = {\n"
                config_str = config_str .. "    deadzone = " .. tostring(input_settings.deadzone) .. ",\n"
                config_str = config_str .. "    vibration_enabled = " .. tostring(input_settings.vibration_enabled) .. ",\n"
                config_str = config_str .. "    vibration_strength = " .. tostring(input_settings.vibration_strength) .. ",\n"
                config_str = config_str .. "    mobile_vibration_enabled = " .. tostring(input_settings.mobile_vibration_enabled) .. "\n"
                config_str = config_str .. "  }\n"
            end

            config_str = config_str .. "}\n"

            return love.filesystem.write("mobile_config.lua", config_str)
        end)

        if not success then
            dprint("Warning: Could not save mobile config: " .. tostring(err))
            return false
        end
        return true
    end

    -- Desktop: save to config.ini
    local success, err = pcall(function()
        -- Read existing IsDebug value to preserve it
        local existing_is_debug = nil
        local ini = require "engine.utils.ini"
        local existing_config = ini:Read("config.ini")
        if existing_config and existing_config.Game and existing_config.Game.IsDebug ~= nil then
            existing_is_debug = existing_config.Game.IsDebug
        end

        local file = io.open("config.ini", "w")
        if file then
            file:write("[Game]\n")
            -- Version is hardcoded in conf.lua, not saved to config.ini
            -- Preserve existing IsDebug value (developer-only setting)
            if existing_is_debug ~= nil then
                file:write("IsDebug = " .. tostring(existing_is_debug) .. "\n")
            end
            file:write("\n")
            file:write("[Window]\n")
            -- Save selected windowed resolution (not current window/fullscreen size)
            local width, height
            if resolution_override then
                width = resolution_override.w
                height = resolution_override.h
            elseif GameConfig.windowed_width and GameConfig.windowed_height then
                -- Use stored windowed resolution
                width = GameConfig.windowed_width
                height = GameConfig.windowed_height
            else
                -- Fallback to GameConfig values
                width = GameConfig.width
                height = GameConfig.height
            end
            file:write("Width = " .. width .. "\n")
            file:write("Height = " .. height .. "\n")
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

            -- Write Input settings if provided
            if input_settings then
                file:write("\n")
                file:write("[Input]\n")
                file:write("Deadzone = " .. tostring(input_settings.deadzone) .. "\n")
                file:write("VibrationEnabled = " .. tostring(input_settings.vibration_enabled) .. "\n")
                file:write("VibrationStrength = " .. tostring(input_settings.vibration_strength) .. "\n")
                file:write("MobileVibrationEnabled = " .. tostring(input_settings.mobile_vibration_enabled) .. "\n")
            end

            file:close()
            return true
        end
        return false
    end)

    if not success then
        dprint("Warning: Could not save config: " .. tostring(err))
        return false
    end

    return true
end

function utils:ReadOrCreateConfig()
    -- Don't try on mobile platforms
    if not love.system then return false end
    local os_name = love.system.getOS()
    if os_name == "Android" or os_name == "iOS" then return false end

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
        dprint("Warning: Could not read/create config: " .. tostring(err))
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

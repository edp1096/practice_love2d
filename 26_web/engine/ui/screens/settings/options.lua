-- engine/ui/screens/settings/options.lua
-- Options management for settings menu

local options = {}

local input = require "engine.core.input"
local sound = require "engine.core.sound"
local display = require "engine.core.display"
local utils = require "engine.utils.util"
local constants = require "engine.core.constants"

-- Resolution presets (desktop only)
options.resolutions = {
    { w = 640,  h = 360,  name = "640x360" },
    { w = 854,  h = 480,  name = "854x480" },
    { w = 960,  h = 540,  name = "960x540" },
    { w = 1280, h = 720,  name = "1280x720" },
    { w = 1600, h = 900,  name = "1600x900" },
    { w = 1920, h = 1080, name = "1920x1080" },
    { w = 2560, h = 1440, name = "2560x1440" },
    { w = 3840, h = 2160, name = "3840x2160" },
}

-- Volume presets (0%, 25%, 50%, 75%, 100%)
options.volume_levels = { 0.0, 0.25, 0.5, 0.75, 1.0 }

-- Vibration strength presets (0%, 25%, 50%, 75%, 100%)
options.vibration_strengths = { 0.0, 0.25, 0.5, 0.75, 1.0 }

-- Deadzone presets (0.05 ~ 0.30)
options.deadzones = { 0.05, 0.10, 0.15, 0.20, 0.25, 0.30 }

-- Build options list based on platform
function options:buildOptions(is_mobile, monitor_count)
    local option_list = {}

    -- Desktop-only options
    if not is_mobile then
        table.insert(option_list, { name = "Resolution", type = "list" })
        table.insert(option_list, { name = "Fullscreen", type = "toggle" })

        -- Only show Monitor option if multiple monitors exist
        if monitor_count > 1 then
            table.insert(option_list, { name = "Monitor", type = "cycle" })
        end
    end

    -- Add sound options (both desktop and mobile)
    table.insert(option_list, { name = "Master Volume", type = "percent" })
    table.insert(option_list, { name = "BGM Volume", type = "percent" })
    table.insert(option_list, { name = "SFX Volume", type = "percent" })
    table.insert(option_list, { name = "Mute", type = "toggle" })

    -- Add gamepad settings if controller is connected
    if input:hasGamepad() then
        table.insert(option_list, { name = "Vibration", type = "toggle" })
        table.insert(option_list, { name = "Vibration Strength", type = "percent" })
        table.insert(option_list, { name = "Deadzone", type = "deadzone" })
    end

    -- Add mobile vibration option for Android/iOS
    if is_mobile then
        table.insert(option_list, { name = "Mobile Vibration", type = "toggle" })
    end

    table.insert(option_list, { name = "Back", type = "action" })

    return option_list
end

-- Find current resolution index in provided resolution list
function options:findCurrentResolution(resolutions)
    -- When in fullscreen, read windowed resolution (what user selected)
    -- When in windowed mode, read current window size
    local current_w, current_h
    if APP_CONFIG.fullscreen then
        current_w = APP_CONFIG.windowed_width or APP_CONFIG.width
        current_h = APP_CONFIG.windowed_height or APP_CONFIG.height
    else
        current_w = APP_CONFIG.width
        current_h = APP_CONFIG.height
    end

    -- Use provided resolutions or fall back to default list
    local res_list = resolutions or self.resolutions

    for i, res in ipairs(res_list) do
        if res.w == current_w and res.h == current_h then return i end
    end

    return 3 -- Default to index 3 (usually 960x540)
end

-- Find volume level index
function options:findVolumeLevel(current_volume)
    for i, volume in ipairs(self.volume_levels) do
        if math.abs(volume - current_volume) < 0.01 then return i end
    end

    return 5 -- Default to 100%
end

-- Find vibration strength index
function options:findVibrationStrength()
    local current = input.settings.vibration_strength
    for i, strength in ipairs(self.vibration_strengths) do
        if math.abs(strength - current) < 0.01 then return i end
    end

    return 5 -- Default to 100%
end

-- Find deadzone index
function options:findDeadzone()
    local current = input.settings.deadzone
    for i, dz in ipairs(self.deadzones) do
        if math.abs(dz - current) < 0.01 then return i end
    end

    return 3 -- Default to 0.15
end

-- Get option value string for display
function options:getOptionValue(state, index)
    local option = state.options[index]

    if option.name == "Resolution" then
        return state.resolutions and state.resolutions[state.current_resolution_index] and state.resolutions[state.current_resolution_index].name or "N/A"
    elseif option.name == "Fullscreen" then
        return APP_CONFIG.fullscreen and "On" or "Off"
    elseif option.name == "Monitor" then
        return state.monitors and state.monitors[state.current_monitor_index] and state.monitors[state.current_monitor_index].name or "N/A"
    elseif option.name == "Master Volume" then
        return string.format("%.0f%%", self.volume_levels[state.current_master_volume_index] * 100)
    elseif option.name == "BGM Volume" then
        return string.format("%.0f%%", self.volume_levels[state.current_bgm_volume_index] * 100)
    elseif option.name == "SFX Volume" then
        return string.format("%.0f%%", self.volume_levels[state.current_sfx_volume_index] * 100)
    elseif option.name == "Mute" then
        return sound.settings.muted and "On" or "Off"
    elseif option.name == "Vibration" then
        return input.settings.vibration_enabled and "On" or "Off"
    elseif option.name == "Mobile Vibration" then
        return input.settings.mobile_vibration_enabled and "On" or "Off"
    elseif option.name == "Vibration Strength" then
        return string.format("%.0f%%", self.vibration_strengths[state.current_vibration_index] * 100)
    elseif option.name == "Deadzone" then
        return string.format("%.2f", self.deadzones[state.current_deadzone_index])
    elseif option.name == "Back" then
        return ""
    end

    return ""
end

-- Helper: Cycle through an array index (wraps around)
local function cycleIndex(current_index, array, direction)
    local new_index = current_index + direction
    if new_index < 1 then
        return #array
    elseif new_index > #array then
        return 1
    end
    return new_index
end

-- Helper: Sync and save sound config
local function syncAndSaveSoundConfig()
    APP_CONFIG.sound.master_volume = sound.settings.master_volume
    APP_CONFIG.sound.bgm_volume = sound.settings.bgm_volume
    APP_CONFIG.sound.sfx_volume = sound.settings.sfx_volume
    APP_CONFIG.sound.muted = sound.settings.muted
    utils:SaveConfig(APP_CONFIG, sound.settings, nil, nil)
end

-- Helper: Sync and save input config
local function syncAndSaveInputConfig()
    APP_CONFIG.input.vibration_enabled = input.settings.vibration_enabled
    APP_CONFIG.input.mobile_vibration_enabled = input.settings.mobile_vibration_enabled
    APP_CONFIG.input.vibration_strength = input.settings.vibration_strength
    APP_CONFIG.input.deadzone = input.settings.deadzone
    utils:SaveConfig(APP_CONFIG, sound.settings, input.settings, nil)
end

-- Option change handlers (data-driven)
local option_handlers = {
    ["Resolution"] = function(self, state, direction)
        if not state.resolutions or #state.resolutions == 0 then return end

        state.current_resolution_index = cycleIndex(state.current_resolution_index, state.resolutions, direction)

        local res = state.resolutions[state.current_resolution_index]
        -- Always update windowed resolution (what user selected)
        APP_CONFIG.windowed_width, APP_CONFIG.windowed_height = res.w, res.h

        if not APP_CONFIG.fullscreen then
            -- Windowed mode: apply resolution immediately
            APP_CONFIG.width, APP_CONFIG.height = res.w, res.h
            love.window.updateMode(res.w, res.h, {
                resizable = APP_CONFIG.resizable,
                display = state.current_monitor_index
            })
            display:CalculateScale()
            if state.resize then state:resize(res.w, res.h) end
        else
            -- Fullscreen mode: don't change width/height (keep monitor resolution)
            -- But update previous_screen_wh for when user exits fullscreen
            display.previous_screen_wh.w = res.w
            display.previous_screen_wh.h = res.h
        end
        utils:SaveConfig(APP_CONFIG, sound.settings, input.settings, state.resolutions[state.current_resolution_index])
        sound:playSFX("menu", "navigate")
    end,

    ["Fullscreen"] = function(self, state, direction)
        -- ToggleFullScreen now handles windowed resolution management internally
        display:ToggleFullScreen()

        -- Get dimensions for resize callback
        local current_w, current_h = display:GetScreenDimensions()

        display:CalculateScale()
        if state.resize then state:resize(current_w, current_h) end
        utils:SaveConfig(APP_CONFIG, sound.settings, input.settings, state.resolutions[state.current_resolution_index])
        sound:playSFX("menu", "navigate")
    end,

    ["Monitor"] = function(self, state, direction)
        if not state.monitors or #state.monitors == 0 then return end

        state.current_monitor_index = cycleIndex(state.current_monitor_index, state.monitors, direction)

        APP_CONFIG.monitor = state.current_monitor_index
        display.window.display = state.current_monitor_index

        if APP_CONFIG.fullscreen then
            display:DisableFullScreen()
            display:EnableFullScreen()
        else
            local dx, dy = love.window.getDesktopDimensions(state.current_monitor_index)
            local x = dx / 2 - APP_CONFIG.width / 2
            local y = dy / 2 - APP_CONFIG.height / 2
            display.window.x = x
            display.window.y = y
            love.window.updateMode(APP_CONFIG.width, APP_CONFIG.height, {
                resizable = APP_CONFIG.resizable,
                display = state.current_monitor_index
            })
        end

        display:CalculateScale()
        if state.resize then state:resize(APP_CONFIG.width, APP_CONFIG.height) end
        utils:SaveConfig(APP_CONFIG, sound.settings, input.settings, state.resolutions[state.current_resolution_index])
        sound:playSFX("menu", "navigate")
    end,

    ["Master Volume"] = function(self, state, direction)
        state.current_master_volume_index = cycleIndex(state.current_master_volume_index, self.volume_levels, direction)
        sound:setMasterVolume(self.volume_levels[state.current_master_volume_index])
        syncAndSaveSoundConfig()
        sound:playSFX("menu", "navigate")
    end,

    ["BGM Volume"] = function(self, state, direction)
        state.current_bgm_volume_index = cycleIndex(state.current_bgm_volume_index, self.volume_levels, direction)
        sound:setBGMVolume(self.volume_levels[state.current_bgm_volume_index])
        syncAndSaveSoundConfig()
    end,

    ["SFX Volume"] = function(self, state, direction)
        state.current_sfx_volume_index = cycleIndex(state.current_sfx_volume_index, self.volume_levels, direction)
        sound:setSFXVolume(self.volume_levels[state.current_sfx_volume_index])
        syncAndSaveSoundConfig()
        sound:playSFX("menu", "navigate")
    end,

    ["Mute"] = function(self, state, direction)
        sound:toggleMute()
        syncAndSaveSoundConfig()
    end,

    ["Vibration"] = function(self, state, direction)
        input:setVibrationEnabled(not input.settings.vibration_enabled)
        syncAndSaveInputConfig()
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK
            input:vibrate(v.duration, v.left, v.right)
        end
    end,

    ["Mobile Vibration"] = function(self, state, direction)
        input:setMobileVibrationEnabled(not input.settings.mobile_vibration_enabled)
        syncAndSaveInputConfig()
        if input.settings.mobile_vibration_enabled then
            local v = constants.VIBRATION.ATTACK
            input:vibrate(v.duration, v.left, v.right)
        end
    end,

    ["Vibration Strength"] = function(self, state, direction)
        state.current_vibration_index = cycleIndex(state.current_vibration_index, self.vibration_strengths, direction)
        input:setVibrationStrength(self.vibration_strengths[state.current_vibration_index])
        syncAndSaveInputConfig()
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK
            input:vibrate(v.duration, v.left, v.right)
        end
    end,

    ["Deadzone"] = function(self, state, direction)
        state.current_deadzone_index = cycleIndex(state.current_deadzone_index, self.deadzones, direction)
        input:setDeadzone(self.deadzones[state.current_deadzone_index])
        syncAndSaveInputConfig()
    end
}

-- Change option value
function options:changeOption(state, direction)
    local option = state.options[state.selected]
    local handler = option_handlers[option.name]

    if handler then
        handler(self, state, direction)
    else
        print("WARNING: No handler for option '" .. tostring(option.name) .. "'")
    end
end

return options

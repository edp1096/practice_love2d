-- engine/ui/screens/settings/options.lua
-- Options management for settings menu

local options = {}

local input = require "engine.core.input"
local sound = require "engine.core.sound"
local display = require "engine.core.display"
local utils = require "engine.utils.util"
local constants = require "engine.core.constants"
local locale = require "engine.core.locale"

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
-- Uses internal keys for logic, name for display (translated via locale)
function options:buildOptions(is_mobile, monitor_count)
    local option_list = {}

    -- Helper to add option with translated name
    local function addOption(key, opt_type)
        table.insert(option_list, {
            key = key,  -- Internal key for handlers
            name = locale:t("settings." .. key),  -- Translated display name
            type = opt_type
        })
    end

    -- Desktop-only options (hide on mobile and web)
    if not is_mobile and love.system.getOS() ~= "Web" then
        addOption("resolution", "list")
        addOption("fullscreen", "toggle")

        -- Only show Monitor option if multiple monitors exist
        if monitor_count > 1 then
            addOption("monitor", "cycle")
        end
    end

    -- Add sound options (both desktop and mobile)
    addOption("master_volume", "percent")
    addOption("bgm_volume", "percent")
    addOption("sfx_volume", "percent")
    addOption("mute", "toggle")

    -- Add language option
    addOption("language", "language")

    -- Add gamepad settings if controller is connected
    if input:hasGamepad() then
        addOption("vibration", "toggle")
        addOption("vibration_strength", "percent")
        addOption("deadzone", "deadzone")
    end

    -- Add mobile vibration option for Android/iOS
    if is_mobile then
        addOption("mobile_vibration", "toggle")
    end

    table.insert(option_list, { key = "back", name = locale:t("common.back"), type = "action" })

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
    local key = option.key or option.name  -- Support both key (new) and name (legacy)

    -- Helper for On/Off display
    local function onOff(value)
        return value and locale:t("common.on") or locale:t("common.off")
    end

    if key == "resolution" then
        return state.resolutions and state.resolutions[state.current_resolution_index] and state.resolutions[state.current_resolution_index].name or "N/A"
    elseif key == "fullscreen" then
        return onOff(APP_CONFIG.fullscreen)
    elseif key == "monitor" then
        return state.monitors and state.monitors[state.current_monitor_index] and state.monitors[state.current_monitor_index].name or "N/A"
    elseif key == "master_volume" then
        return string.format("%.0f%%", self.volume_levels[state.current_master_volume_index] * 100)
    elseif key == "bgm_volume" then
        return string.format("%.0f%%", self.volume_levels[state.current_bgm_volume_index] * 100)
    elseif key == "sfx_volume" then
        return string.format("%.0f%%", self.volume_levels[state.current_sfx_volume_index] * 100)
    elseif key == "mute" then
        return onOff(sound.settings.muted)
    elseif key == "language" then
        -- Display current language name
        local current = locale:getLocale()
        return current == "en" and "English" or current == "ko" and "한국어" or current
    elseif key == "vibration" then
        return onOff(input.settings.vibration_enabled)
    elseif key == "mobile_vibration" then
        return onOff(input.settings.mobile_vibration_enabled)
    elseif key == "vibration_strength" then
        return string.format("%.0f%%", self.vibration_strengths[state.current_vibration_index] * 100)
    elseif key == "deadzone" then
        return string.format("%.2f", self.deadzones[state.current_deadzone_index])
    elseif key == "back" then
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

-- Option change handlers (data-driven, use keys)
local option_handlers = {
    ["resolution"] = function(self, state, direction)
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

    ["fullscreen"] = function(self, state, direction)
        -- ToggleFullScreen now handles windowed resolution management internally
        display:ToggleFullScreen()

        -- Get dimensions for resize callback
        local current_w, current_h = display:GetScreenDimensions()

        display:CalculateScale()
        if state.resize then state:resize(current_w, current_h) end
        utils:SaveConfig(APP_CONFIG, sound.settings, input.settings, state.resolutions[state.current_resolution_index])
        sound:playSFX("menu", "navigate")
    end,

    ["monitor"] = function(self, state, direction)
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

    ["master_volume"] = function(self, state, direction)
        state.current_master_volume_index = cycleIndex(state.current_master_volume_index, self.volume_levels, direction)
        sound:setMasterVolume(self.volume_levels[state.current_master_volume_index])
        syncAndSaveSoundConfig()
        sound:playSFX("menu", "navigate")
    end,

    ["bgm_volume"] = function(self, state, direction)
        state.current_bgm_volume_index = cycleIndex(state.current_bgm_volume_index, self.volume_levels, direction)
        sound:setBGMVolume(self.volume_levels[state.current_bgm_volume_index])
        syncAndSaveSoundConfig()
    end,

    ["sfx_volume"] = function(self, state, direction)
        state.current_sfx_volume_index = cycleIndex(state.current_sfx_volume_index, self.volume_levels, direction)
        sound:setSFXVolume(self.volume_levels[state.current_sfx_volume_index])
        syncAndSaveSoundConfig()
        sound:playSFX("menu", "navigate")
    end,

    ["mute"] = function(self, state, direction)
        sound:toggleMute()
        syncAndSaveSoundConfig()
    end,

    ["language"] = function(self, state, direction)
        -- Cycle through available locales
        locale:cycleLocale()
        -- Rebuild options with new translations
        local is_mobile = (love._os == "Android" or love._os == "iOS")
        state.options = options:buildOptions(is_mobile, state.monitor_count or 1)
        -- Update fonts for new locale
        local fonts = require "engine.utils.fonts"
        state.titleFont = locale:getFont("title") or fonts.title
        state.labelFont = locale:getFont("option") or fonts.option
        state.valueFont = locale:getFont("option") or fonts.option
        state.hintFont = locale:getFont("hint") or fonts.hint
        -- Save locale setting
        utils:SaveConfig(APP_CONFIG, sound.settings, input.settings, nil)
        sound:playSFX("menu", "navigate")
    end,

    ["vibration"] = function(self, state, direction)
        input:setVibrationEnabled(not input.settings.vibration_enabled)
        syncAndSaveInputConfig()
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK
            input:vibrate(v.duration, v.left, v.right)
        end
    end,

    ["mobile_vibration"] = function(self, state, direction)
        input:setMobileVibrationEnabled(not input.settings.mobile_vibration_enabled)
        syncAndSaveInputConfig()
        if input.settings.mobile_vibration_enabled then
            local v = constants.VIBRATION.ATTACK
            input:vibrate(v.duration, v.left, v.right)
        end
    end,

    ["vibration_strength"] = function(self, state, direction)
        state.current_vibration_index = cycleIndex(state.current_vibration_index, self.vibration_strengths, direction)
        input:setVibrationStrength(self.vibration_strengths[state.current_vibration_index])
        syncAndSaveInputConfig()
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK
            input:vibrate(v.duration, v.left, v.right)
        end
    end,

    ["deadzone"] = function(self, state, direction)
        state.current_deadzone_index = cycleIndex(state.current_deadzone_index, self.deadzones, direction)
        input:setDeadzone(self.deadzones[state.current_deadzone_index])
        syncAndSaveInputConfig()
    end,

    ["back"] = function(self, state, direction)
        -- Back action is handled by input module, not here
        -- This is just to suppress the warning
    end
}

-- Change option value
function options:changeOption(state, direction)
    local option = state.options[state.selected]
    local key = option.key or option.name  -- Support both key (new) and name (legacy)
    local handler = option_handlers[key]

    if handler then
        handler(self, state, direction)
    else
        print("WARNING: No handler for option '" .. tostring(key) .. "'")
    end
end

return options

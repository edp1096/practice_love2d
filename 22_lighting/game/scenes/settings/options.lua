-- scenes/settings/options.lua
-- Options management for settings menu

local options = {}

local input = require "engine.input"
local sound = require "engine.sound"
local display = require "engine.display"
local utils = require "engine.utils.util"
local constants = require "engine.constants"

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

-- Filter resolutions by monitor size
function options:filterResolutions()
    for i = #self.resolutions, 1, -1 do
        local res = self.resolutions[i]
        local w, h = love.window.getDesktopDimensions()
        if res.w > w or res.h > h then
            table.remove(self.resolutions, i)
        end
    end
end

-- Find current resolution index
function options:findCurrentResolution()
    local current_w = GameConfig.width
    local current_h = GameConfig.height

    for i, res in ipairs(self.resolutions) do
        if res.w == current_w and res.h == current_h then return i end
    end

    return 3 -- Default to 960x540
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
        return GameConfig.fullscreen and "On" or "Off"
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

-- Change option value
function options:changeOption(state, direction)
    local option = state.options[state.selected]

    if option.name == "Resolution" then
        if not state.resolutions or #state.resolutions == 0 then return end

        state.current_resolution_index = state.current_resolution_index + direction
        if state.current_resolution_index < 1 then
            state.current_resolution_index = #state.resolutions
        elseif state.current_resolution_index > #state.resolutions then
            state.current_resolution_index = 1
        end

        -- Apply resolution
        local res = state.resolutions[state.current_resolution_index]
        GameConfig.width, GameConfig.height = res.w, res.h
        GameConfig.windowed_width, GameConfig.windowed_height = res.w, res.h
        if not GameConfig.fullscreen then
            love.window.updateMode(res.w, res.h, {
                resizable = GameConfig.resizable,
                display = state.current_monitor_index
            })
            display:CalculateScale()
            -- CRITICAL: Call resize chain like window resize does
            if state.resize then state:resize(res.w, res.h) end
        else
            -- If in fullscreen, update previous_screen_wh so it applies when returning to windowed
            display.previous_screen_wh.w = res.w
            display.previous_screen_wh.h = res.h
        end
        utils:SaveConfig(GameConfig, nil, nil, state.resolutions[state.current_resolution_index])

        -- Play navigate sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "Fullscreen" then
        -- CRITICAL FIX: Always call resize chain for both fullscreen and windowed
        display:ToggleFullScreen()
        GameConfig.fullscreen = display.is_fullscreen

        -- Get current dimensions (different for fullscreen vs windowed)
        local current_w, current_h
        if GameConfig.fullscreen then
            -- Fullscreen: use desktop dimensions
            current_w, current_h = love.window.getDesktopDimensions(state.current_monitor_index)
        else
            -- Windowed: use config dimensions
            current_w, current_h = GameConfig.width, GameConfig.height
            love.window.updateMode(current_w, current_h, {
                resizable = GameConfig.resizable,
                display = state.current_monitor_index
            })
        end

        display:CalculateScale()
        -- CRITICAL: Always call resize chain (both fullscreen and windowed)
        -- This propagates to pause → play → camera:zoomTo()
        if state.resize then state:resize(current_w, current_h) end

        utils:SaveConfig(GameConfig, nil, nil, state.resolutions[state.current_resolution_index])

        -- Play navigate sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "Monitor" then
        if not state.monitors or #state.monitors == 0 then return end

        state.current_monitor_index = state.current_monitor_index + direction
        if state.current_monitor_index < 1 then
            state.current_monitor_index = #state.monitors
        elseif state.current_monitor_index > #state.monitors then
            state.current_monitor_index = 1
        end

        -- Update monitor in config and screen
        GameConfig.monitor = state.current_monitor_index
        display.window.display = state.current_monitor_index

        if GameConfig.fullscreen then
            -- For fullscreen, disable then re-enable on new monitor
            display:DisableFullScreen()
            display:EnableFullScreen()
        else
            -- For windowed mode, calculate centered position on target monitor
            local dx, dy = love.window.getDesktopDimensions(state.current_monitor_index)
            local x = dx / 2 - GameConfig.width / 2
            local y = dy / 2 - GameConfig.height / 2

            display.window.x = x
            display.window.y = y

            love.window.updateMode(GameConfig.width, GameConfig.height, {
                resizable = GameConfig.resizable,
                display = state.current_monitor_index
            })
        end

        -- Recalculate screen after monitor change
        display:CalculateScale()
        -- CRITICAL: Call resize chain
        if state.resize then state:resize(GameConfig.width, GameConfig.height) end
        utils:SaveConfig(GameConfig, nil, nil, state.resolutions[state.current_resolution_index])

        -- Play navigate sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "Master Volume" then
        state.current_master_volume_index = state.current_master_volume_index + direction
        if state.current_master_volume_index < 1 then
            state.current_master_volume_index = #self.volume_levels
        elseif state.current_master_volume_index > #self.volume_levels then
            state.current_master_volume_index = 1
        end

        sound:setMasterVolume(self.volume_levels[state.current_master_volume_index])

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings, nil, state.resolutions[state.current_resolution_index])

        -- Test sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "BGM Volume" then
        state.current_bgm_volume_index = state.current_bgm_volume_index + direction
        if state.current_bgm_volume_index < 1 then
            state.current_bgm_volume_index = #self.volume_levels
        elseif state.current_bgm_volume_index > #self.volume_levels then
            state.current_bgm_volume_index = 1
        end

        sound:setBGMVolume(self.volume_levels[state.current_bgm_volume_index])

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings, nil, state.resolutions[state.current_resolution_index])
    elseif option.name == "SFX Volume" then
        state.current_sfx_volume_index = state.current_sfx_volume_index + direction
        if state.current_sfx_volume_index < 1 then
            state.current_sfx_volume_index = #self.volume_levels
        elseif state.current_sfx_volume_index > #self.volume_levels then
            state.current_sfx_volume_index = 1
        end

        sound:setSFXVolume(self.volume_levels[state.current_sfx_volume_index])

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings, nil, state.resolutions[state.current_resolution_index])

        -- Test sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "Mute" then
        sound:toggleMute()

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings, nil, state.resolutions[state.current_resolution_index])
    elseif option.name == "Vibration" then
        input:setVibrationEnabled(not input.settings.vibration_enabled)

        -- Sync to GameConfig before saving
        GameConfig.input.vibration_enabled = input.settings.vibration_enabled
        utils:SaveConfig(GameConfig, sound.settings, input.settings, state.resolutions[state.current_resolution_index])

        -- Test vibration when enabling
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK; input:vibrate(v.duration, v.left, v.right)
        end
    elseif option.name == "Mobile Vibration" then
        input:setMobileVibrationEnabled(not input.settings.mobile_vibration_enabled)

        -- Sync to GameConfig before saving
        GameConfig.input.mobile_vibration_enabled = input.settings.mobile_vibration_enabled
        utils:SaveConfig(GameConfig, sound.settings, input.settings, state.resolutions[state.current_resolution_index])

        -- Test vibration when enabling
        if input.settings.mobile_vibration_enabled then
            local v = constants.VIBRATION.ATTACK; input:vibrate(v.duration, v.left, v.right)
        end
    elseif option.name == "Vibration Strength" then
        state.current_vibration_index = state.current_vibration_index + direction
        if state.current_vibration_index < 1 then
            state.current_vibration_index = #self.vibration_strengths
        elseif state.current_vibration_index > #self.vibration_strengths then
            state.current_vibration_index = 1
        end

        input:setVibrationStrength(self.vibration_strengths[state.current_vibration_index])

        -- Sync to GameConfig before saving
        GameConfig.input.vibration_strength = input.settings.vibration_strength
        utils:SaveConfig(GameConfig, sound.settings, input.settings, state.resolutions[state.current_resolution_index])

        -- Test vibration
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK; input:vibrate(v.duration, v.left, v.right)
        end
    elseif option.name == "Deadzone" then
        state.current_deadzone_index = state.current_deadzone_index + direction
        if state.current_deadzone_index < 1 then
            state.current_deadzone_index = #self.deadzones
        elseif state.current_deadzone_index > #self.deadzones then
            state.current_deadzone_index = 1
        end

        input:setDeadzone(self.deadzones[state.current_deadzone_index])

        -- Sync to GameConfig before saving
        GameConfig.input.deadzone = input.settings.deadzone
        utils:SaveConfig(GameConfig, sound.settings, input.settings, state.resolutions[state.current_resolution_index])
    end
end

return options

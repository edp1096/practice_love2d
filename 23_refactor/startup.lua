-- startup.lua
-- Initialization utilities for conf.lua and main.lua
-- Extracts complex setup logic to keep entry points clean and readable

local startup = {}

-- === Error Handling ===

function startup.errorHandler(msg)
    msg = tostring(msg)
    local trace = debug.traceback("Error: " .. msg, 2):gsub("\n[^\n]+$", "")

    print("=== FATAL ERROR ===")
    print(trace)

    local log_path = love.filesystem.getSaveDirectory() .. "/crash.log"
    local success, file = pcall(io.open, log_path, "w")
    if success and file then
        file:write("LOVE2D Crash Report\n")
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        file:write(trace .. "\n")
        file:close()
        print("Crash log written to: " .. log_path)
    end

    pcall(function()
        love.filesystem.write("crash.log", trace)
        print("Crash log also saved to: " .. love.filesystem.getSaveDirectory() .. "/crash.log")
    end)

    return function()
        love.event.quit()
    end
end

-- === Platform Detection ===

-- For conf.lua (early initialization, before love.system is available)
function startup.detectPlatform_early()
    local is_android = love._os == "Android"
    local is_mobile = is_android or love._os == "iOS"
    return is_mobile, is_android
end

-- For main.lua (runtime, after love.system is initialized)
function startup.detectPlatform_runtime()
    local is_android = love.system.getOS() == "Android"
    local is_mobile = is_android or love.system.getOS() == "iOS"
    return is_mobile, is_android
end

-- === Configuration Loading ===

-- Load desktop configuration from config.ini (for conf.lua)
function startup.loadDesktopConfig()
    local ini = require "engine.utils.ini"
    local util = require "engine.utils.util"
    local convert = require "engine.utils.convert"

    local success, err = pcall(util.ReadOrCreateConfig, util)
    if not success then
        print("Warning: Could not read/create config: " .. tostring(err))
    end

    local success2, config, err2 = pcall(ini.Read, ini, "config.ini")
    if success2 and config and not err2 then
        -- Load Game settings if available
        if config.Game then
            -- Version is hardcoded in conf.lua, not loaded from config.ini
            if config.Game.IsDebug ~= nil then
                -- ini parser already converts "true"/"false" to boolean
                GameConfig.is_debug = config.Game.IsDebug
            end
        end

        -- Load Window settings (properly handle nil vs false)
        if config.Window then
            if config.Window.Width then
                GameConfig.width = config.Window.Width
                GameConfig.windowed_width = config.Window.Width
            end
            if config.Window.Height then
                GameConfig.height = config.Window.Height
                GameConfig.windowed_height = config.Window.Height
            end
            if config.Window.Resizable ~= nil then
                GameConfig.resizable = config.Window.Resizable
            end
            if config.Window.FullScreen ~= nil then
                GameConfig.fullscreen = config.Window.FullScreen
            end
            if config.Window.Monitor then
                GameConfig.monitor = config.Window.Monitor
            end
        end

        -- Load Sound settings if available
        if config.Sound then
            GameConfig.sound.master_volume = convert:toPercent(config.Sound.MasterVolume, GameConfig.sound.master_volume)
            GameConfig.sound.bgm_volume = convert:toPercent(config.Sound.BGMVolume, GameConfig.sound.bgm_volume)
            GameConfig.sound.sfx_volume = convert:toPercent(config.Sound.SFXVolume, GameConfig.sound.sfx_volume)
            GameConfig.sound.muted = convert:toBool(config.Sound.Muted, GameConfig.sound.muted)
        end

        -- Load Input settings if available
        if config.Input then
            if config.Input.Deadzone then
                GameConfig.input.deadzone = convert:toNumberClamped(config.Input.Deadzone, 0.05, 0.30, 0.15)
            end
            if config.Input.VibrationEnabled ~= nil then
                GameConfig.input.vibration_enabled = convert:toBool(config.Input.VibrationEnabled)
            end
            if config.Input.VibrationStrength then
                GameConfig.input.vibration_strength = convert:toPercent(config.Input.VibrationStrength, 1.0)
            end
            if config.Input.MobileVibrationEnabled ~= nil then
                GameConfig.input.mobile_vibration_enabled = convert:toBool(config.Input.MobileVibrationEnabled)
            end
        end
    end
end

-- Load mobile configuration from mobile_config.lua (for main.lua)
function startup.loadMobileConfig()
    local success, mobile_config = pcall(function()
        local content = love.filesystem.read("mobile_config.lua")
        if content then
            local chunk = load(content)
            if chunk then
                return chunk()
            end
        end
        return nil
    end)

    if success and mobile_config then
        if mobile_config.sound then
            if mobile_config.sound.master_volume ~= nil then
                GameConfig.sound.master_volume = mobile_config.sound.master_volume
            end
            if mobile_config.sound.bgm_volume ~= nil then
                GameConfig.sound.bgm_volume = mobile_config.sound.bgm_volume
            end
            if mobile_config.sound.sfx_volume ~= nil then
                GameConfig.sound.sfx_volume = mobile_config.sound.sfx_volume
            end
            if mobile_config.sound.muted ~= nil then
                GameConfig.sound.muted = mobile_config.sound.muted
            end
        end
        if mobile_config.input then
            if mobile_config.input.deadzone ~= nil then
                GameConfig.input.deadzone = mobile_config.input.deadzone
            end
            if mobile_config.input.vibration_enabled ~= nil then
                GameConfig.input.vibration_enabled = mobile_config.input.vibration_enabled
            end
            if mobile_config.input.vibration_strength ~= nil then
                GameConfig.input.vibration_strength = mobile_config.input.vibration_strength
            end
            if mobile_config.input.mobile_vibration_enabled ~= nil then
                GameConfig.input.mobile_vibration_enabled = mobile_config.input.mobile_vibration_enabled
            end
        end
    end
end

-- Initialize application (called from love.load)
-- Returns modules needed for system.handleHotkey()
function startup.initialize(is_mobile, modules)
    -- Load mobile config if on mobile
    if is_mobile then
        startup.loadMobileConfig()
    end

    -- Initialize sound system AFTER loading config
    local sound_data = require "game.data.sounds"
    modules.sound:init(sound_data)

    -- Initialize input system with config
    local input_config = require "game.data.input_config"
    modules.input:init(input_config)

    -- Configure game-specific dependencies (delegated to game/setup.lua)
    local game_setup = require "game.setup"
    game_setup.configure()

    -- Setup scene loader
    modules.scene_control.scene_loader = game_setup.getSceneLoader()

    -- Setup input dispatcher
    modules.input_dispatcher.scene_control = modules.scene_control
    modules.input_dispatcher.virtual_gamepad = modules.virtual_gamepad
    modules.input_dispatcher.input = modules.input
    modules.input_dispatcher.is_mobile = is_mobile

    -- Setup app lifecycle
    modules.lifecycle.display = modules.display
    modules.lifecycle.input = modules.input
    modules.lifecycle.virtual_gamepad = modules.virtual_gamepad
    modules.lifecycle.fonts = modules.fonts
    modules.lifecycle.scene_control = modules.scene_control
    modules.lifecycle.utils = modules.utils
    modules.lifecycle.sound = modules.sound
    modules.lifecycle.effects = modules.effects
    modules.lifecycle.GameConfig = GameConfig
    modules.lifecycle.is_mobile = is_mobile

    -- Initialize coordinate system (must be after display initialization)
    -- Note: camera is scene-specific, so coords will use it dynamically
    modules.coords:init(nil, modules.display)

    -- Initialize application
    modules.lifecycle:initialize(modules.menu)

    -- Return modules needed for system.handleHotkey() (used in love.keypressed)
    return {
        display = modules.display,
        utils = modules.utils,
        lifecycle = modules.lifecycle,
        sound = modules.sound,
        input = modules.input
    }
end

return startup

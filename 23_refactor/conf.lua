-- conf.lua
local ini = require "engine.utils.ini"
local util = require "engine.utils.util"
local convert = require "engine.utils.convert"

-- Detect platform early
local is_android = love._os == "Android"
local is_mobile = is_android or love._os == "iOS"

GameConfig = {
    version = "0.0.1",  -- Hardcoded version (not saved to config.ini)
    is_debug = true,  -- Temporarily enabled for debugging

    width = 1280,
    height = 720,
    windowed_width = 1280,  -- Selected resolution (saved to config)
    windowed_height = 720,  -- Selected resolution (saved to config)
    resizable = false,
    fullscreen = false,
    vsync = true,
    scale_mode = "fit",

    min_width = 640,
    min_height = 360,

    -- Sound settings (defaults)
    sound = {
        master_volume = 1.0,
        bgm_volume = 0.7,
        sfx_volume = 0.8,
        muted = false
    },

    -- Input settings (defaults)
    input = {
        deadzone = 0.15,
        vibration_enabled = true,
        vibration_strength = 1.0,
        mobile_vibration_enabled = true
    }
}

-- Only try to read config on desktop
if not is_mobile then
    local success, err = pcall(util.ReadOrCreateConfig, util)
    if not success then
        dprint("Warning: Could not read/create config: " .. tostring(err))
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
else
    -- Mobile: load from love.filesystem
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
            -- Use nil check instead of 'or' to preserve false/0.0 values
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

function love.conf(t)
    t.identity = "hello_love2d"
    -- t.version = "11.5"
    t.console = false

    t.window.title = "Hello Love2D"
    t.window.icon = nil

    if is_mobile then
        -- Mobile: use device screen size
        t.window.width = 0
        t.window.height = 0
        t.window.borderless = false
        t.window.resizable = false
        t.window.fullscreen = false
        t.window.fullscreentype = "desktop"
        t.window.vsync = 1
    else
        -- Desktop: use config
        t.window.width = GameConfig.width
        t.window.height = GameConfig.height
        t.window.borderless = false
        t.window.resizable = GameConfig.resizable
        t.window.fullscreen = false
        t.window.fullscreentype = "desktop"
        t.window.vsync = GameConfig.vsync and 1 or 0
        t.window.minwidth = GameConfig.min_width
        t.window.minheight = GameConfig.min_height
    end

    t.window.display = 1
    t.window.highdpi = false
    t.window.usedpiscale = true
    t.window.depth = nil
    t.window.stencil = nil

    t.modules.audio = true
    t.modules.data = true
    t.modules.event = true
    t.modules.font = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.joystick = true
    t.modules.keyboard = true
    t.modules.math = true
    t.modules.mouse = true
    t.modules.physics = true
    t.modules.sound = true
    t.modules.system = true
    t.modules.thread = true
    t.modules.timer = true
    t.modules.touch = true
    t.modules.video = false
    t.modules.window = true
end

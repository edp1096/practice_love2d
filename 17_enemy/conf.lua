-- conf.lua
local ini = require "lib.ini"
local util = require "utils.util"

-- Detect platform early
local is_android = love._os == "Android"
local is_mobile = is_android or love._os == "iOS"

GameConfig = {
    title = "Hello Love2D",
    author = "Your Name",
    version = "0.0.1",

    width = 1280,
    height = 720,
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
    }
}

-- Only try to read config on desktop
if not is_mobile then
    local success, err = pcall(util.ReadOrCreateConfig, util)
    if not success then
        print("Warning: Could not read/create config: " .. tostring(err))
    end

    local success2, config, err2 = pcall(ini.Read, ini, "config.ini")
    if success2 and config and not err2 then
        GameConfig.width = config.Window.Width or GameConfig.width
        GameConfig.height = config.Window.Height or GameConfig.height
        GameConfig.resizable = config.Window.Resizable or GameConfig.resizable
        GameConfig.fullscreen = config.Window.FullScreen or GameConfig.fullscreen
        GameConfig.monitor = config.Window.Monitor or 1

        -- Load Sound settings if available
        if config.Sound then
            GameConfig.sound.master_volume = tonumber(config.Sound.MasterVolume) or GameConfig.sound.master_volume
            GameConfig.sound.bgm_volume = tonumber(config.Sound.BGMVolume) or GameConfig.sound.bgm_volume
            GameConfig.sound.sfx_volume = tonumber(config.Sound.SFXVolume) or GameConfig.sound.sfx_volume
            GameConfig.sound.muted = (config.Sound.Muted == "true") or GameConfig.sound.muted
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
        print("Loading mobile config...")
        if mobile_config.sound then
            GameConfig.sound.master_volume = mobile_config.sound.master_volume or GameConfig.sound.master_volume
            GameConfig.sound.bgm_volume = mobile_config.sound.bgm_volume or GameConfig.sound.bgm_volume
            GameConfig.sound.sfx_volume = mobile_config.sound.sfx_volume or GameConfig.sound.sfx_volume
            GameConfig.sound.muted = mobile_config.sound.muted or GameConfig.sound.muted
            print("Mobile sound settings loaded")
        end
    end
end

function love.conf(t)
    t.identity = "hello_love2d"
    t.version = "11.5"
    t.console = false

    t.window.title = GameConfig.title
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

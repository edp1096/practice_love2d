-- conf.lua
local startup = require "startup"

-- Detect platform early
local is_mobile = startup.detectPlatform_early()

APP_CONFIG = {
    version = "0.0.1", -- Hardcoded version (not saved to config.ini)
    is_debug = false,  -- Debug mode off by default (set IsDebug=true in config.ini to enable)

    width = 1280,
    height = 720,
    windowed_width = 1280, -- Selected resolution (saved to config)
    windowed_height = 720, -- Selected resolution (saved to config)
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
    },

    -- HUD settings (game-specific, injected from game/data/hud.lua)
    hud = nil  -- Will be loaded in startup.lua
}

-- Load desktop config (mobile config loaded in main.lua)
if not is_mobile then startup.loadDesktopConfig() end

function love.conf(t)
    t.identity = "hello_love2d" -- Save directory
    -- t.version = "11.5"
    t.console = false
    t.highdpi = true  -- LÖVE 12.0: moved from t.window.highdpi

    -- LÖVE 12.0: Renderer selection (Vulkan has vsync issues on Windows/Linux)
    -- Desktop: Prefer OpenGL over Vulkan (Vulkan vsync broken)
    -- Mobile: Use default (OpenGL ES on Android, Metal on iOS)
    t.graphics = t.graphics or {}
    if love.system.getOS() == "Windows" or love.system.getOS() == "Linux" then
        -- t.graphics.renderers = {"opengl", "vulkan"}  -- OpenGL first, Vulkan fallback
        t.graphics.renderers = {"opengl"}  -- OpenGL first, Vulkan fallback
    elseif love.system.getOS() == "OS X" or love.system.getOS() == "iOS" then
        t.graphics.renderers = {"metal", "opengl"}   -- Metal first (OpenGL deprecated)
    else
        -- Android, unknown platforms: use default order
        t.graphics.renderers = nil
    end

    t.window.title = "Hello Love2D"
    t.window.icon = nil

    -- Common window settings
    t.window.borderless = false
    t.window.fullscreen = false
    t.window.fullscreentype = "desktop"
    t.window.displayindex = 1
    t.window.usedpiscale = true
    t.window.depth = nil
    t.window.stencil = nil

    -- Mobile: use device screen size
    t.window.width = 0
    t.window.height = 0
    t.window.resizable = false
    t.window.vsync = 0
    if not is_mobile then
        -- Desktop: use config
        t.window.width = APP_CONFIG.width
        t.window.height = APP_CONFIG.height
        t.window.resizable = APP_CONFIG.resizable
        -- LÖVE 12.0: Use regular vsync (1) instead of adaptive (-1) for stable frame timing
        t.window.vsync = 1
        t.window.minwidth = APP_CONFIG.min_width
        t.window.minheight = APP_CONFIG.min_height
    end

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

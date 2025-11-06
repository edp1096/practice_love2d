-- conf.lua
-- Configuration file for LÖVE2D

-- Detect platform early
local is_android = love._os == "Android"
local is_mobile = is_android or love._os == "iOS"

function love.conf(t)
    t.identity = "hello_love2d"
    t.version = "11.5"
    t.console = false

    t.window.title = "Hello Love2D - LÖVE2D"
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
        t.window.width = 1280
        t.window.height = 720
        t.window.borderless = false
        t.window.resizable = true
        t.window.fullscreen = false
        t.window.fullscreentype = "desktop"
        t.window.vsync = 1
        t.window.minwidth = 640
        t.window.minheight = 360
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

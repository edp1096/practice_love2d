local ini = require "lib.ini"
local util = require "utils.util"

GameConfig = {
    title = "Hello Love2D",
    author = "Your Name",
    version = "0.0.1",

    width = 1280,
    height = 720,
    resizable = false,
    fullscreen = false,
    vsync = true,
    -- scale_mode = "fill",
    scale_mode = "fit",

    min_width = 640,
    min_height = 360
}

util:ReadOrCreateConfig()

local config, err = ini:Read("config.ini")
if not err then
    GameConfig.width = config and config.Window.Width
    GameConfig.height = config and config.Window.Height
    GameConfig.resizable = config and config.Window.Resizable
    GameConfig.fullscreen = config and config.Window.FullScreen
    GameConfig.monitor = config and config.Window.Monitor
end

function love.conf(t)
    t.title = GameConfig.title
    t.author = GameConfig.author

    t.window.width = GameConfig.width
    t.window.height = GameConfig.height
    t.window.resizable = GameConfig.resizable
    -- t.window.fullscreen = GameConfig.fullscreen -- Not use
    t.window.vsync = GameConfig.vsync
    t.window.minwidth = GameConfig.min_width
    t.window.minheight = GameConfig.min_height

    t.modules.joystick = true
    t.modules.physics = true
    t.modules.touch = false
    t.modules.video = true
end

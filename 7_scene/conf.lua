local ini = require "lib.ini"

GameConfig = {
    title = "Hello Love2D",
    author = "Your Name",
    version = "0.0.1",

    width = 1280,
    height = 720,
    resizable = true,
    fullscreen = false,
    vsync = true,

    min_width = 640,
    min_height = 360
}

local file = io.open("config.ini", "r")
if file then
    file:close()
else
    local data = love.filesystem.read("config.ini")
    if data then
        local f = io.open("config.ini", "w")
        if f then
            f:write(data)
            f:close()
        end
    end
end


local config, err = ini:Read("config.ini")
if not err then
    GameConfig.width = config and config.Window.Width
    GameConfig.height = config and config.Window.Height
    GameConfig.resizable = config and config.Window.Resizable
    GameConfig.fullscreen = config and config.Window.FullScreen
    GameConfig.monitor = config and config.Window.Monitor
    GameConfig.scale_mode = config and config.Window.ScaleMode
    GameConfig.vsync = config and config.Window.Vsync
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

    t.modules.joystick = false
    t.modules.physics = true
    t.modules.touch = false
    t.modules.video = true
end

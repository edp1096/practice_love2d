function love.conf(t)
    t.title = "Hello Love2D"
    t.author = "Your Name"
    -- t.version = "11.5"

    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    -- t.window.fullscreen = false
    t.window.vsync = 1
    t.window.minwidth = 640
    t.window.minheight = 360

    t.modules.joystick = false
    t.modules.physics = true
    t.modules.touch = false
    t.modules.video = true
end

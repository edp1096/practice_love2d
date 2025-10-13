function love.conf(t)
    t.title = "Hello Love2D" -- Window title
    t.author = "Your Name"   -- Author name
    -- t.version = "11.5"       -- Love2D version

    -- Window settings
    t.window.width = 1280     -- Default window width
    t.window.height = 720     -- Default window height
    t.window.resizable = true -- Allow window resizing
    -- t.window.fullscreen = false -- Start in windowed mode
    t.window.vsync = 1        -- Enable vsync
    t.window.minwidth = 640   -- Minimum window width
    t.window.minheight = 360  -- Minimum window height

    -- Disable unused modules for better performance
    t.modules.joystick = false -- Disable joystick module
    t.modules.physics = false  -- Disable physics module
    t.modules.touch = false    -- Disable touch module
    t.modules.video = false    -- Disable video module
end

local is_debug = false

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LOVE " .. love_version .. " and Lua " .. _VERSION)

local virtual_resolution = require "lib.virtual_resolution"

local vres, logo
-- local screen_width, screen_height = love.window.getDesktopDimensions(1)
-- print("Screen: " .. screen_width .. "x" .. screen_height)
-- local render_width, render_height = screen_width, screen_height
local render_width, render_height = 1280, 720

local window_mode = {
    fullscreen = false,
    fullscreentype = "desktop",
    vsync = true,
    -- msaa = 0,
    -- stecil = 0,
    -- depth = 0,
    -- resizable = true,
    -- borderless = false,
    -- centered = false,
    resizable = false,
    borderless = false,
    centered = true,
    display = 1,
    highdpi = true,
    usedpiscale = true,
    minwidth = 640,
    minheight = 360,
    -- x = 0,
    -- y = 0
}

function love.load()
    _ = love.window.setMode(render_width, render_height, window_mode)
    vres = virtual_resolution.new(1280, 720)
    -- love.window.setFullscreen(false)

    logo = love.graphics.newImage("assets/images/logo.png")
end

function love.draw()
    vres:Attatch()
    love.graphics.draw(logo, 0, 0)
    vres:Detatch()

    if is_debug then
        vres:ShowDebugInfo()
    end
end

function love.resize(w, h)
    vres:resize(w, h)
end

function love.keypressed(key)
    if key == "f11" then
        local isFullscreen = love.window.getFullscreen()
        love.window.setFullscreen(not isFullscreen, "desktop")
    elseif key == "f12" then
        is_debug = not is_debug
    end

    if key == "1" then
        vres:setScaleMode("fit")
    elseif key == "2" then
        vres:setScaleMode("fill")
    end
end

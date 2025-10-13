local is_debug = false

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LOVE " .. love_version .. " and Lua " .. _VERSION)

local virtual_resolution = require "lib.virtual_resolution"
local pcm = require "lib.sound"

local vres, logo, player


function love.load()
    vres = virtual_resolution.new(1280, 720)
    love.window.setFullscreen(false)

    logo = love.graphics.newImage("assets/images/logo.png")

    player = {}
    player.x = 400
    player.y = 200
    player.speed = 5
end

function love.update(dt)
    if love.keyboard.isDown("right") then
        player.x = player.x + player.speed
    end
    if love.keyboard.isDown("left") then
        player.x = player.x - player.speed
    end
    if love.keyboard.isDown("down") then
        player.y = player.y + player.speed
    end
    if love.keyboard.isDown("up") then
        player.y = player.y - player.speed
    end
end

function love.draw()
    vres:Attatch()
    love.graphics.draw(logo, 0, 0)
    vres:Detatch()

    love.graphics.circle("fill", player.x, player.y, 100)

    if is_debug then
        vres:ShowDebugInfo()
    end
end

function love.resize(w, h)
    vres:resize(w, h)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f10" then
        local vres_scale_mode = vres:getScaleMode()
        print("ScaleMode: " .. vres_scale_mode)
        if vres_scale_mode ~= "fit" then
            vres:setScaleMode("fit")
        else
            vres:setScaleMode("fill")
        end
    elseif key == "f11" then
        local isFullscreen = love.window.getFullscreen()
        love.window.setFullscreen(not isFullscreen)
    elseif key == "f12" then
        pcm:PlaySound()
        is_debug = not is_debug
    end
end

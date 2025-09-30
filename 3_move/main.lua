local is_debug = false

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LOVE " .. love_version .. " and Lua " .. _VERSION)

local virtual_resolution = require "lib.virtual_resolution"
local pcm = require "lib.sound"

local cwd = love.filesystem.getWorkingDirectory()

local player = require "player"

local vres, logo
local background


function love.load()
    vres = virtual_resolution.new(GameConfig.width, GameConfig.height)
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.window.setFullscreen(false)

    local sprite_sheet = "assets/images/player-sheet.png"
    player:New(sprite_sheet)

    background = love.graphics.newImage("assets/images/background.png")
end

function love.update(dt)
    player:Update(dt)
end

function love.draw()
    vres:Attatch()
    love.graphics.draw(background, 0, 0)
    player.anim:draw(player.spriteSheet, player.x, player.y, nil, 10, 10)
    vres:Detatch()

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

local is_debug = false

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LOVE " .. love_version .. " and " .. _VERSION)


local locker
if _VERSION == "Lua 5.1" then
    locker = require "locker"
end

local screen = require "lib.screen"
local sti = require "vendor.sti"
local camera = require("vendor.hump.camera")
local cam = camera()
local player = require "player"
local utils = require "utils"

local cwd = love.filesystem.getWorkingDirectory()
local game_map


function love.load()
    if locker then locker:ProcInit() end

    screen:Initialize(GameConfig)

    game_map = sti("maps/level1/test_map.lua")

    local sprite_sheet = "assets/images/player-sheet.png"
    player:New(sprite_sheet)
end

function love.update(dt)
    player:Update(dt)
    print(player.x, player.y)
    cam:lookAt(player.x, player.y)
end

function love.draw()
    -- screen:Attatch()
    cam:attach()
    game_map:draw()
    player.anim:draw(player.spriteSheet, player.x, player.y, nil, 10, 10)
    cam:detach()
    -- screen:Detatch()

    if is_debug then screen:ShowDebugInfo() end
end

function love.resize(w, h)
    screen:Resize()

    GameConfig.width = w
    GameConfig.height = h

    utils:SaveConfig(GameConfig)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "f10" then
        GameConfig.scale_mode = screen:GetScaleMode()
        if GameConfig.scale_mode ~= "fit" then
            GameConfig.scale_mode = "fit"
        else
            GameConfig.scale_mode = "fill"
        end
        screen:SetScaleMode(GameConfig.scale_mode)
        utils:SaveConfig(GameConfig)
    elseif key == "f11" then
        screen:ToggleFullScreen()
    elseif key == "f12" then
        is_debug = not is_debug
    end
end

function love.quit()
    if locker then locker:ProcQuit() end
end

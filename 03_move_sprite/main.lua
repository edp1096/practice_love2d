local is_debug = false

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LOVE " .. love_version .. " and " .. _VERSION)

local locker
if _VERSION == "Lua 5.1" then
    locker = require "locker"
end
local screen = require "lib.screen"
local player = require "player"
local sound = require "lib.sound"
local utils = require "utils"


local cwd = love.filesystem.getWorkingDirectory()

local logo
local background


function love.load()
    if locker then locker:ProcInit() end

    screen:Initialize(GameConfig)

    local sprite_sheet = "assets/images/player-sheet.png"
    player:New(sprite_sheet)

    background = love.graphics.newImage("assets/images/background.png")
end

function love.update(dt)
    player:Update(dt)
end

function love.draw()
    screen:Attatch()
    love.graphics.draw(background, 0, 0)
    player.anim:draw(player.spriteSheet, player.x, player.y, nil, 10, 10)
    screen:Detatch()

    if is_debug then
        screen:ShowDebugInfo()
    end
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
        sound:PlaySound()
        is_debug = not is_debug
    end
end

function love.quit()
    if locker then locker:ProcQuit() end
end

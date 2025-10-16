-- main.lua
-- Entry point with unified debug system

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LÖVE " .. love_version .. " and " .. _VERSION)

local locker
if _VERSION == "Lua 5.1" then locker = require "locker" end

local debug = require "systems.debug"
local screen = require "lib.screen"
local utils = require "utils.util"
local scene_control = require "systems.scene_control"
local menu = require "scenes.menu"

function love.load()
    if locker then locker:ProcInit() end

    screen:Initialize(GameConfig)
    love.graphics.setDefaultFilter("nearest", "nearest")

    scene_control.switch(menu)
end

function love.update(dt) scene_control.update(dt) end

function love.draw() scene_control.draw() end

function love.resize(w, h)
    -- Global resize handling
    GameConfig.width = w
    GameConfig.height = h
    utils:SaveConfig(GameConfig)
    screen:CalculateScale()

    scene_control.resize(w, h)
end

function love.keypressed(key)
    -- Global keys that work in all scenes
    if key == "f11" then
        -- Toggle fullscreen
        screen:ToggleFullScreen()
        GameConfig.fullscreen = screen.is_fullscreen
        utils:SaveConfig(GameConfig)

        scene_control.resize(love.graphics.getWidth(), love.graphics.getHeight())
    elseif key == "f12" then
        -- Legacy key: F12 still works for backwards compatibility
        -- But F3 is the new standard (handled by debug:handleInput in scenes)
        debug:toggle()
    end

    scene_control.keypressed(key)
end

function love.mousepressed(x, y, button)
    scene_control.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    scene_control.mousereleased(x, y, button)
end

function love.quit()
    local current_w, current_h, current_flags = love.window.getMode()
    if not screen.is_fullscreen then
        GameConfig.width = current_w
        GameConfig.height = current_h
    end
    GameConfig.monitor = current_flags.display
    utils:SaveConfig(GameConfig)

    if locker then locker:ProcQuit() end
end

-- main.lua
-- Game entry point

function love.errorhandler(msg)
    msg = tostring(msg)
    local trace = debug.traceback("Error: " .. msg, 2):gsub("\n[^\n]+$", "")

    print("=== FATAL ERROR ===")
    print(trace)

    local log_path = love.filesystem.getSaveDirectory() .. "/crash.log"
    local success, file = pcall(io.open, log_path, "w")
    if success and file then
        file:write("LOVE2D Crash Report\n")
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        file:write(trace .. "\n")
        file:close()
        print("Crash log written to: " .. log_path)
    end

    pcall(function()
        love.filesystem.write("crash.log", trace)
        print("Crash log also saved to: " .. love.filesystem.getSaveDirectory() .. "/crash.log")
    end)

    return function()
        love.event.quit()
    end
end

local love_version = (love._version_major .. "." .. love._version_minor)

local is_android = love.system.getOS() == "Android"
local is_mobile = is_android or love.system.getOS() == "iOS"

local locker
if not is_mobile and _VERSION == "Lua 5.1" then
    local success, result = pcall(require, "locker")
    if success then
        locker = result
    else
        print("Warning: Could not load locker module: " .. tostring(result))
    end
end


-- Define global dprint BEFORE loading other modules that might use it
local debug = require "engine.debug"
_G.dprint = function(...) debug:dprint(...) end

-- Print version info
dprint("Running with LOVE " .. love_version .. " and " .. _VERSION)

-- Now load other modules (they can safely use dprint)
local screen = require "engine.display"  -- Global for Talkies compatibility
local utils = require "engine.utils.util"
local scene_control = require "engine.scene_control"
local input = require "engine.input"
local input_dispatcher = require "engine.input.dispatcher"
local lifecycle = require "engine.lifecycle"
local sound = require "engine.sound"
local fonts = require "engine.utils.fonts"
local coords = require "engine.coords"
local menu = require "game.scenes.menu"

local virtual_gamepad
if is_mobile then
    virtual_gamepad = require "engine.input.virtual_gamepad"
end

-- === Application Lifecycle ===

function love.load()
    -- Setup input dispatcher
    input_dispatcher.scene_control = scene_control
    input_dispatcher.virtual_gamepad = virtual_gamepad
    input_dispatcher.input = input
    input_dispatcher.is_mobile = is_mobile

    -- Setup app lifecycle
    lifecycle.locker = locker
    lifecycle.screen = screen
    lifecycle.input = input
    lifecycle.virtual_gamepad = virtual_gamepad
    lifecycle.fonts = fonts
    lifecycle.scene_control = scene_control
    lifecycle.utils = utils
    lifecycle.sound = sound
    lifecycle.GameConfig = GameConfig
    lifecycle.is_mobile = is_mobile

    -- Initialize coordinate system (must be after screen initialization)
    -- Note: camera is scene-specific, so coords will use it dynamically
    coords:init(nil, screen)

    -- Initialize application
    lifecycle:initialize(menu)
end

function love.update(dt) lifecycle:update(dt) end

function love.draw() lifecycle:draw() end

function love.resize(w, h) lifecycle:resize(w, h) end

-- === Input Event Handlers ===

function love.keypressed(key)
    -- Handle system-level hotkeys (F11, F1)
    if key == "f11" and not is_mobile then
        screen:ToggleFullScreen()
        GameConfig.fullscreen = screen.is_fullscreen
        pcall(utils.SaveConfig, utils, GameConfig, sound.settings)
        lifecycle:resize(love.graphics.getWidth(), love.graphics.getHeight())
        return
    elseif key == "f1" then
        debug:toggle()
        return
    end

    -- Delegate all other input to dispatcher
    input_dispatcher:keypressed(key)
end

function love.mousepressed(x, y, button) input_dispatcher:mousepressed(x, y, button) end

function love.mousereleased(x, y, button) input_dispatcher:mousereleased(x, y, button) end

function love.touchpressed(id, x, y, dx, dy, pressure) input_dispatcher:touchpressed(id, x, y, dx, dy, pressure) end

function love.touchreleased(id, x, y, dx, dy, pressure) input_dispatcher:touchreleased(id, x, y, dx, dy, pressure) end

function love.touchmoved(id, x, y, dx, dy, pressure) input_dispatcher:touchmoved(id, x, y, dx, dy, pressure) end

function love.joystickadded(joystick) input_dispatcher:joystickadded(joystick) end

function love.joystickremoved(joystick) input_dispatcher:joystickremoved(joystick) end

function love.gamepadpressed(joystick, button) input_dispatcher:gamepadpressed(joystick, button) end

function love.gamepadreleased(joystick, button) input_dispatcher:gamepadreleased(joystick, button) end

function love.gamepadaxis(joystick, axis, value) input_dispatcher:gamepadaxis(joystick, axis, value) end

function love.quit() lifecycle:quit() end

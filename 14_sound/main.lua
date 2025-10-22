-- main.lua
-- Entry point with unified debug system, gamepad support, and Android virtual gamepad

local love_version = (love._version_major .. "." .. love._version_minor)
print("Running with LÖVE " .. love_version .. " and " .. _VERSION)

-- Detect platform
local is_android = love.system.getOS() == "Android"
local is_mobile = is_android or love.system.getOS() == "iOS"

-- Only use locker on desktop platforms
local locker
if not is_mobile and _VERSION == "Lua 5.1" then
    local success, result = pcall(require, "locker")
    if success then
        locker = result
    else
        print("Warning: Could not load locker module: " .. tostring(result))
    end
end

local debug = require "systems.debug"
local screen = require "lib.screen"
local utils = require "utils.util"
local scene_control = require "systems.scene_control"
local input = require "systems.input"
local menu = require "scenes.menu"

-- Virtual gamepad for Android
local virtual_gamepad
if is_mobile then
    virtual_gamepad = require "systems.virtual_gamepad"
end

function love.load()
    if locker then
        local success, err = pcall(locker.ProcInit, locker)
        if not success then
            print("Warning: Locker init failed: " .. tostring(err))
        end
    end

    -- Safe screen initialization
    local success, err = pcall(screen.Initialize, screen, GameConfig)
    if not success then
        print("ERROR: Screen initialization failed: " .. tostring(err))
        -- Fallback: set basic values
        screen.screen_wh.w, screen.screen_wh.h = love.graphics.getDimensions()
        screen.render_wh.w, screen.render_wh.h = 960, 540
        screen.scale = math.min(
            screen.screen_wh.w / screen.render_wh.w,
            screen.screen_wh.h / screen.render_wh.h
        )
        screen.offset_x = (screen.screen_wh.w - screen.render_wh.w * screen.scale) / 2
        screen.offset_y = (screen.screen_wh.h - screen.render_wh.h * screen.scale) / 2
    end

    input:init()

    -- Initialize virtual gamepad for mobile
    if virtual_gamepad then
        virtual_gamepad:init()
        input:setVirtualGamepad(virtual_gamepad)
        print("Virtual gamepad enabled for mobile platform")
    end

    scene_control.switch(menu)
end

function love.update(dt)
    input:update(dt)
    scene_control.update(dt)
end

function love.draw()
    scene_control.draw()

    -- Draw virtual gamepad overlay on top of everything
    if virtual_gamepad and virtual_gamepad.enabled then
        virtual_gamepad:draw()
    end
end

function love.resize(w, h)
    GameConfig.width = w
    GameConfig.height = h

    -- Safe config save (may not work on all platforms)
    if not is_mobile then
        pcall(utils.SaveConfig, utils, GameConfig)
    end

    pcall(screen.CalculateScale, screen)
    scene_control.resize(w, h)

    -- Update virtual gamepad positions
    if virtual_gamepad then
        virtual_gamepad:resize(w, h)
    end
end

function love.keypressed(key)
    if key == "f11" and not is_mobile then
        screen:ToggleFullScreen()
        GameConfig.fullscreen = screen.is_fullscreen
        if not is_mobile then
            pcall(utils.SaveConfig, utils, GameConfig)
        end
        scene_control.resize(love.graphics.getWidth(), love.graphics.getHeight())
    elseif key == "f12" then
        debug:toggle()
    end

    scene_control.keypressed(key)
end

function love.mousepressed(x, y, button)
    -- Ignore mouse events on mobile (touch events are used instead)
    if virtual_gamepad and virtual_gamepad.enabled then
        return
    end
    scene_control.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    -- Ignore mouse events on mobile (touch events are used instead)
    if virtual_gamepad and virtual_gamepad.enabled then
        return
    end
    scene_control.mousereleased(x, y, button)
end

-- Touch support for mobile with virtual gamepad integration
function love.touchpressed(id, x, y, dx, dy, pressure)
    -- First check if virtual gamepad handled it
    if virtual_gamepad and virtual_gamepad:touchpressed(id, x, y) then
        return -- Virtual gamepad consumed the touch, don't pass to scene
    end

    -- Pass to scene if it has touch handler
    if scene_control.current and scene_control.current.touchpressed then
        scene_control.current:touchpressed(id, x, y, dx, dy, pressure)
    elseif not is_mobile then
        -- Fallback for PC touchscreens: treat as mouse click
        love.mousepressed(x, y, 1)
    end
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    -- First check if virtual gamepad handled it
    if virtual_gamepad and virtual_gamepad:touchreleased(id, x, y) then
        return -- Virtual gamepad consumed the touch, don't pass to scene
    end

    -- Pass to scene if it has touch handler
    if scene_control.current and scene_control.current.touchreleased then
        scene_control.current:touchreleased(id, x, y, dx, dy, pressure)
    elseif not is_mobile then
        -- Fallback for PC touchscreens: treat as mouse release
        love.mousereleased(x, y, 1)
    end
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    -- First check if virtual gamepad handled it
    if virtual_gamepad and virtual_gamepad:touchmoved(id, x, y) then
        return -- Virtual gamepad consumed the touch, don't pass to scene
    end

    -- Otherwise pass to scene
    if scene_control.current and scene_control.current.touchmoved then
        scene_control.current:touchmoved(id, x, y, dx, dy, pressure)
    end
end

-- Gamepad callbacks
function love.joystickadded(joystick)
    input:joystickAdded(joystick)
end

function love.joystickremoved(joystick)
    input:joystickRemoved(joystick)
end

function love.gamepadpressed(joystick, button)
    if scene_control.current and scene_control.current.gamepadpressed then
        scene_control.current:gamepadpressed(joystick, button)
    end
end

function love.gamepadreleased(joystick, button)
    if scene_control.current and scene_control.current.gamepadreleased then
        scene_control.current:gamepadreleased(joystick, button)
    end
end

function love.gamepadaxis(joystick, axis, value)
    if scene_control.current and scene_control.current.gamepadaxis then
        scene_control.current:gamepadaxis(joystick, axis, value)
    end
end

function love.quit()
    if not is_mobile then
        local current_w, current_h, current_flags = love.window.getMode()
        if not screen.is_fullscreen then
            GameConfig.width = current_w
            GameConfig.height = current_h
        end
        GameConfig.monitor = current_flags.display
        pcall(utils.SaveConfig, utils, GameConfig)
    end

    if locker then
        pcall(locker.ProcQuit, locker)
    end
end

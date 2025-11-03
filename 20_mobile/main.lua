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
print("Running with LOVE " .. love_version .. " and " .. _VERSION)

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

local debug = require "systems.debug"
local screen = require "lib.screen"
local utils = require "utils.util"
local scene_control = require "systems.scene_control"
local input = require "systems.input"
local sound = require "systems.sound"
local menu = require "scenes.menu"

local virtual_gamepad
if is_mobile then
    virtual_gamepad = require "systems.input.virtual_gamepad"
end

function love.load()
    if locker then
        local success, err = pcall(locker.ProcInit, locker)
        if not success then
            print("Warning: Locker init failed: " .. tostring(err))
        end
    end

    local success, err = pcall(screen.Initialize, screen, GameConfig)
    if not success then
        print("ERROR: Screen initialization failed: " .. tostring(err))
        screen.screen_wh = { w = 0, h = 0 }
        screen.render_wh = { w = 960, h = 540 }
        screen.screen_wh.w, screen.screen_wh.h = love.graphics.getDimensions()
        screen.scale = math.min(
            screen.screen_wh.w / screen.render_wh.w,
            screen.screen_wh.h / screen.render_wh.h
        )
        screen.offset_x = (screen.screen_wh.w - screen.render_wh.w * screen.scale) / 2
        screen.offset_y = (screen.screen_wh.h - screen.render_wh.h * screen.scale) / 2
    end

    input:init()

    if virtual_gamepad then
        virtual_gamepad:init()
        input:setVirtualGamepad(virtual_gamepad)
        print("Virtual gamepad enabled for mobile OS")
    end

    scene_control.switch(menu)
end

function love.update(dt)
    input:update(dt)

    if virtual_gamepad then
        virtual_gamepad:update(dt)
    end

    scene_control.update(dt)
end

function love.draw()
    scene_control.draw()

    -- Draw virtual gamepad
    if virtual_gamepad and virtual_gamepad.enabled then
        virtual_gamepad:draw()
    end

    if screen then
        screen:ShowDebugInfo()
        screen:ShowVirtualMouse()
    end
end

function love.resize(w, h)
    GameConfig.width = w
    GameConfig.height = h

    pcall(utils.SaveConfig, utils, GameConfig, sound.settings)

    pcall(screen.CalculateScale, screen)
    scene_control.resize(w, h)

    if virtual_gamepad then
        virtual_gamepad:resize(w, h)
    end
end

function love.keypressed(key)
    if key == "f11" and not is_mobile then
        screen:ToggleFullScreen()
        GameConfig.fullscreen = screen.is_fullscreen
        if not is_mobile then
            pcall(utils.SaveConfig, utils, GameConfig, sound.settings)
        end
        scene_control.resize(love.graphics.getWidth(), love.graphics.getHeight())
    elseif key == "f12" then
        debug:toggle()
        return
    end

    scene_control.keypressed(key)
end

function love.mousepressed(x, y, button)
    if virtual_gamepad and virtual_gamepad.enabled then
        return
    end
    scene_control.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    if virtual_gamepad and virtual_gamepad.enabled then
        return
    end
    scene_control.mousereleased(x, y, button)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
    -- 1. Debug button has highest priority
    if scene_control.current and scene_control.current.debug_button then
        local btn = scene_control.current.debug_button
        local in_button = x >= btn.x and x <= btn.x + btn.size and
            y >= btn.y and y <= btn.y + btn.size
        if in_button then
            if scene_control.current.touchpressed then
                scene_control.current:touchpressed(id, x, y, dx, dy, pressure)
            end
            return
        end
    end

    -- 2. Scene touchpressed (for overlay scenes like inventory, dialogue, etc.)
    if scene_control.current and scene_control.current.touchpressed then
        local handled = scene_control.current:touchpressed(id, x, y, dx, dy, pressure)
        if handled then
            return
        end
    end

    -- 3. Virtual gamepad (only if scene didn't handle it)
    if virtual_gamepad and virtual_gamepad:touchpressed(id, x, y) then
        return
    end

    -- 4. Fallback to mouse event for desktop testing
    if not is_mobile then
        love.mousepressed(x, y, 1)
    end
end

function love.touchreleased(id, x, y, dx, dy, pressure)
    if scene_control.current and scene_control.current.debug_button then
        local btn = scene_control.current.debug_button
        local in_button = x >= btn.x and x <= btn.x + btn.size and
            y >= btn.y and y <= btn.y + btn.size
        if in_button or btn.touch_id == id then
            if scene_control.current.touchreleased then
                scene_control.current:touchreleased(id, x, y, dx, dy, pressure)
            end
            return
        end
    end

    if virtual_gamepad then
        local handled = virtual_gamepad:touchreleased(id, x, y)
        if handled then
            return
        else
            if scene_control.current and scene_control.current.mousereleased then
                scene_control.current:mousereleased(x, y, 1)
                return
            end
        end
    end

    if scene_control.current and scene_control.current.touchreleased then
        scene_control.current:touchreleased(id, x, y, dx, dy, pressure)
    elseif not is_mobile then
        love.mousereleased(x, y, 1)
    end
end

function love.touchmoved(id, x, y, dx, dy, pressure)
    if virtual_gamepad and virtual_gamepad:touchmoved(id, x, y) then
        return
    end

    if scene_control.current and scene_control.current.touchmoved then
        scene_control.current:touchmoved(id, x, y, dx, dy, pressure)
    end
end

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
    local current_w, current_h, current_flags = love.window.getMode()
    if not is_mobile and not screen.is_fullscreen then
        GameConfig.width = current_w
        GameConfig.height = current_h
        GameConfig.monitor = current_flags.display
    end
    pcall(utils.SaveConfig, utils, GameConfig, sound.settings)

    if locker then
        pcall(locker.ProcQuit, locker)
    end
end

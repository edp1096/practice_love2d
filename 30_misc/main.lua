-- main.lua
-- Game entry point

local startup = require "startup"
local system = require "system"

function love.errorhandler(msg) return startup.errorHandler(msg) end

local love_version = (love._version_major .. "." .. love._version_minor)
local is_mobile = startup.detectPlatform_runtime()
system.preventDuplicateInstance(is_mobile) -- Prevent duplicate game instances

local debug = require "engine.core.debug"
debug.allowed = APP_CONFIG.is_debug -- Allow F1-F6 keys if true
debug.enabled = false               -- Debug UI starts OFF, user must press F1 to enable
_G.dprint = function(...) debug:dprint(...) end

dprint("Running with LOVE " .. love_version .. " and " .. _VERSION)

-- Now load other modules (they can safely use dprint)
local display = require "engine.core.display"
_G.screen = display -- Global reference for display system
local utils = require "engine.utils.util"
local scene_control = require "engine.core.scene_control"
local input = require "engine.core.input"
local input_dispatcher = require "engine.core.input.dispatcher"
local lifecycle = require "engine.core.lifecycle"
local sound = require "engine.core.sound"
local fonts = require "engine.utils.fonts"
local coords = require "engine.core.coords"
local effects = require "engine.systems.effects"
local menu = require "game.scenes.menu"

-- Always load virtual_gamepad (needed for PC debug mode testing)
local virtual_gamepad = require "engine.core.input.virtual_gamepad"

-- === Application Lifecycle ===

local hotkey_modules = nil -- Modules for system.handleHotkey()

function love.load()
    hotkey_modules = startup.initialize(is_mobile, {
        display = display,
        input = input,
        sound = sound,
        scene_control = scene_control,
        input_dispatcher = input_dispatcher,
        virtual_gamepad = virtual_gamepad,
        lifecycle = lifecycle,
        fonts = fonts,
        utils = utils,
        effects = effects,
        coords = coords,
        menu = menu
    })
end

function love.update(dt) lifecycle:update(dt) end

function love.draw() lifecycle:draw() end

function love.resize(w, h) lifecycle:resize(w, h) end

-- === Input Event Handlers ===

function love.keypressed(key)
    -- Handle system-level hotkeys (F11, etc.)
    if system.handleHotkey(key, is_mobile, hotkey_modules) then return end

    -- Delegate all other input to dispatcher
    input_dispatcher:keypressed(key)
end

function love.keyreleased(key) input_dispatcher:keyreleased(key) end

function love.mousepressed(x, y, button) input_dispatcher:mousepressed(x, y, button) end

function love.mousereleased(x, y, button) input_dispatcher:mousereleased(x, y, button) end

function love.mousemoved(x, y, dx, dy) input_dispatcher:mousemoved(x, y, dx, dy) end

function love.wheelmoved(x, y) scene_control.wheelmoved(x, y) end

function love.touchpressed(id, x, y, dx, dy, pressure) input_dispatcher:touchpressed(id, x, y, dx, dy, pressure) end

function love.touchreleased(id, x, y, dx, dy, pressure) input_dispatcher:touchreleased(id, x, y, dx, dy, pressure) end

function love.touchmoved(id, x, y, dx, dy, pressure) input_dispatcher:touchmoved(id, x, y, dx, dy, pressure) end

function love.joystickadded(joystick) input_dispatcher:joystickadded(joystick) end

function love.joystickremoved(joystick) input_dispatcher:joystickremoved(joystick) end

function love.gamepadpressed(joystick, button) input_dispatcher:gamepadpressed(joystick, button) end

function love.gamepadreleased(joystick, button) input_dispatcher:gamepadreleased(joystick, button) end

function love.gamepadaxis(joystick, axis, value) input_dispatcher:gamepadaxis(joystick, axis, value) end

-- === Focus Handler (Web/Mobile Tab Switching) ===

function love.focus(focused)
    if focused then
        -- Tab gained focus - resume BGM if it stopped
        if sound.current_bgm and not sound.current_bgm:isPlaying() then
            -- Reset volume (in case browser muted it)
            local vol = sound.current_bgm:getVolume()
            sound.current_bgm:setVolume(0)
            sound.current_bgm:setVolume(vol)

            -- Multiple play attempts for reliability
            for i = 1, 3 do
                sound.current_bgm:play()
                if sound.current_bgm:isPlaying() then
                    break
                end
            end
        end
    end
    -- Note: Tab loses focus automatically pauses audio in most browsers
    -- This is expected browser behavior and cannot be prevented
end

function love.quit() system.cleanup(lifecycle) end

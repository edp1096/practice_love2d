-- engine/ui/screens/settings/input.lua
-- Input handling for settings menu

local input_handler = {}

local scene_control = require "engine.core.scene_control"
local input = require "engine.core.input"
local sound = require "engine.core.sound"
local options_module = require "engine.ui.screens.settings.options"
local coords = require "engine.core.coords"
local debug = require "engine.core.debug"

function input_handler:keypressed(state, key)
    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process settings keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if key == "escape" then
        sound:playSFX("menu", "back")
        scene_control.pop()
    elseif input:wasPressed("menu_up", "keyboard", key) then
        state.selected = state.selected - 1
        if state.selected < 1 then state.selected = #state.options end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_down", "keyboard", key) then
        state.selected = state.selected + 1
        if state.selected > #state.options then state.selected = 1 end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_left", "keyboard", key) then
        options_module:changeOption(state, -1)
    elseif input:wasPressed("menu_right", "keyboard", key) then
        options_module:changeOption(state, 1)
    elseif input:wasPressed("menu_select", "keyboard", key) then
        if state.options[state.selected].name == "Back" then
            sound:playSFX("menu", "back")
            scene_control.pop()
        else
            options_module:changeOption(state, 1)
        end
    end
end

function input_handler:gamepadpressed(state, joystick, button)
    if input:wasPressed("menu_back", "gamepad", button) then
        sound:playSFX("menu", "back")
        scene_control.pop()
    elseif input:wasPressed("menu_up", "gamepad", button) then
        state.selected = state.selected - 1
        if state.selected < 1 then state.selected = #state.options end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_down", "gamepad", button) then
        state.selected = state.selected + 1
        if state.selected > #state.options then state.selected = 1 end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_left", "gamepad", button) then
        options_module:changeOption(state, -1)
    elseif input:wasPressed("menu_right", "gamepad", button) then
        options_module:changeOption(state, 1)
    elseif input:wasPressed("menu_select", "gamepad", button) then
        if state.options[state.selected].name == "Back" then
            sound:playSFX("menu", "back")
            scene_control.pop()
        else
            options_module:changeOption(state, 1)
        end
    end
end

-- Empty implementation - kept for consistency
function input_handler:mousepressed(state, x, y, button) end

function input_handler:mousereleased(state, x, y, button)
    if button == 1 then
        -- Left mouse button
        if state.mouse_over > 0 then
            state.selected = state.mouse_over

            if state.options[state.selected].name == "Back" then
                sound:playSFX("menu", "back")
                scene_control.pop()
            else
                options_module:changeOption(state, 1)
            end
        end
    elseif button == 2 then
        -- Right mouse button
        if state.mouse_over > 0 and state.options[state.mouse_over].type ~= "action" then
            state.selected = state.mouse_over
            options_module:changeOption(state, -1)
        end
    end
end

-- Touch events are handled the same as mouse for settings menu
-- No return value needed as settings doesn't have gamepad
function input_handler:touchpressed(state, id, x, y, dx, dy, pressure) end

function input_handler:touchreleased(state, id, x, y, dx, dy, pressure)
    -- Convert touch to virtual coordinates for hit detection using coords module
    local display = require "engine.core.display"
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Treat touch release like left mouse click
    self:mousereleased(state, vx, vy, 1)
end

return input_handler

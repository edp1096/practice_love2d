-- engine/ui/screens/inventory/input.lua
-- Input coordinator for inventory UI (delegates to specialized handlers)

local input_handler = {}

-- Import specialized input handlers
local helpers = require "engine.ui.screens.inventory.input.helpers"
local mouse_input = require "engine.ui.screens.inventory.input.mouse"
local keyboard_input = require "engine.ui.screens.inventory.input.keyboard"
local gamepad_input = require "engine.ui.screens.inventory.input.gamepad"
local touch_input = require "engine.ui.screens.inventory.input.touch"

-- Delegate keyboard input to keyboard handler
function input_handler.keypressed(self, key)
    return keyboard_input.keypressed(self, key, helpers)
end

-- Delegate gamepad button input to gamepad handler
function input_handler.gamepadpressed(self, joystick, button)
    return gamepad_input.gamepadpressed(self, joystick, button, helpers)
end

-- Delegate gamepad axis input to gamepad handler
function input_handler.gamepadaxis(self, joystick, axis, value)
    return gamepad_input.gamepadaxis(self, joystick, axis, value)
end

-- Delegate mouse press to mouse handler
function input_handler.mousepressed(self, x, y, button)
    return mouse_input.mousepressed(self, x, y, button, helpers)
end

-- Delegate mouse release to mouse handler
function input_handler.mousereleased(self, x, y, button)
    return mouse_input.mousereleased(self, x, y, button, helpers)
end

-- Delegate mouse movement to mouse handler
function input_handler.mousemoved(self, x, y, dx, dy)
    return mouse_input.mousemoved(self, x, y, dx, dy)
end

-- Delegate touch press to touch handler
function input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
    return touch_input.touchpressed(self, id, x, y, dx, dy, pressure, helpers)
end

-- Delegate touch release to touch handler
function input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
    return touch_input.touchreleased(self, id, x, y, dx, dy, pressure, helpers)
end

-- Expose helper functions (used by other parts of inventory scene)
input_handler.handleClick = helpers.handleClick
input_handler.moveSelection = helpers.moveSelection
input_handler.selectItemByNumber = helpers.selectItemByNumber
input_handler.useSelectedItem = helpers.useSelectedItem

return input_handler

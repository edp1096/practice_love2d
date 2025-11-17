-- engine/ui/screens/inventory/input/touch.lua
-- Touch input handling for inventory (delegates to mouse)

local touch_input = {}

local mouse_input = require "engine.ui.screens.inventory.input.mouse"

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

-- Handle touch input
function touch_input.touchpressed(self, id, x, y, dx, dy, pressure, helpers)
    -- Check if touch is in virtual gamepad area FIRST
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        if virtual_gamepad and virtual_gamepad:isInVirtualPadArea(x, y) then
            -- Let virtual gamepad handle it
            -- Return false immediately without processing the touch
            return false
        end
    end

    -- Handle touch as mouse press (start drag)
    mouse_input.mousepressed(self, x, y, 1, helpers)
    -- Block other handlers
    return true
end

-- Handle touch release (same as mouse release)
function touch_input.touchreleased(self, id, x, y, dx, dy, pressure, helpers)
    -- Check if touch is in virtual gamepad area
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        if virtual_gamepad and virtual_gamepad:isInVirtualPadArea(x, y) then
            return false
        end
    end

    -- Handle touch as mouse release (drop)
    mouse_input.mousereleased(self, x, y, 1, helpers)
    return true
end

return touch_input

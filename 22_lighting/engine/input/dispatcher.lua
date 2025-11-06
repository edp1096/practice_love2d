-- engine/input/dispatcher.lua
-- Centralized input event dispatcher for main.lua
-- Routes LÖVE input events to appropriate handlers (scene_control, virtual_gamepad, etc.)

local input_dispatcher = {}

-- Dependencies (set from main.lua)
input_dispatcher.scene_control = nil
input_dispatcher.virtual_gamepad = nil
input_dispatcher.input = nil
input_dispatcher.is_mobile = false

-- === Keyboard Input ===

function input_dispatcher:keypressed(key)
    -- Delegate to scene_control
    if self.scene_control and self.scene_control.keypressed then
        self.scene_control.keypressed(key)
    end
end

-- === Mouse Input ===

function input_dispatcher:mousepressed(x, y, button)
    -- Block mouse input if virtual gamepad is enabled (mobile mode)
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        return
    end

    if self.scene_control and self.scene_control.mousepressed then
        self.scene_control.mousepressed(x, y, button)
    end
end

function input_dispatcher:mousereleased(x, y, button)
    -- Block mouse input if virtual gamepad is enabled (mobile mode)
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        return
    end

    if self.scene_control and self.scene_control.mousereleased then
        self.scene_control.mousereleased(x, y, button)
    end
end

-- === Touch Input (Mobile) ===

function input_dispatcher:touchpressed(id, x, y, dx, dy, pressure)
    -- Priority 1: Debug button (highest priority)
    if self.scene_control.current and self.scene_control.current.debug_button then
        local btn = self.scene_control.current.debug_button
        local in_button = x >= btn.x and x <= btn.x + btn.size and
                          y >= btn.y and y <= btn.y + btn.size
        if in_button then
            if self.scene_control.current.touchpressed then
                self.scene_control.current:touchpressed(id, x, y, dx, dy, pressure)
            end
            return
        end
    end

    -- Priority 2: Scene touchpressed (for overlay scenes like inventory, dialogue)
    if self.scene_control.current and self.scene_control.current.touchpressed then
        local handled = self.scene_control.current:touchpressed(id, x, y, dx, dy, pressure)
        if handled then
            return
        end
    end

    -- Priority 3: Virtual gamepad (only if scene didn't handle it)
    if self.virtual_gamepad and self.virtual_gamepad:touchpressed(id, x, y) then
        return
    end

    -- Priority 4: Fallback to mouse event for desktop testing
    if not self.is_mobile then
        love.mousepressed(x, y, 1)
    end
end

function input_dispatcher:touchreleased(id, x, y, dx, dy, pressure)
    -- Debug button handling
    if self.scene_control.current and self.scene_control.current.debug_button then
        local btn = self.scene_control.current.debug_button
        local in_button = x >= btn.x and x <= btn.x + btn.size and
                          y >= btn.y and y <= btn.y + btn.size
        if in_button or btn.touch_id == id then
            if self.scene_control.current.touchreleased then
                self.scene_control.current:touchreleased(id, x, y, dx, dy, pressure)
            end
            return
        end
    end

    -- Virtual gamepad handling
    if self.virtual_gamepad then
        local handled = self.virtual_gamepad:touchreleased(id, x, y)
        if handled then
            return
        else
            if self.scene_control.current and self.scene_control.current.mousereleased then
                self.scene_control.current:mousereleased(x, y, 1)
                return
            end
        end
    end

    -- Scene touchreleased or fallback to mouse
    if self.scene_control.current and self.scene_control.current.touchreleased then
        self.scene_control.current:touchreleased(id, x, y, dx, dy, pressure)
    elseif not self.is_mobile then
        love.mousereleased(x, y, 1)
    end
end

function input_dispatcher:touchmoved(id, x, y, dx, dy, pressure)
    -- Virtual gamepad first
    if self.virtual_gamepad and self.virtual_gamepad:touchmoved(id, x, y) then
        return
    end

    -- Scene touchmoved
    if self.scene_control.current and self.scene_control.current.touchmoved then
        self.scene_control.current:touchmoved(id, x, y, dx, dy, pressure)
    end
end

-- === Gamepad Input ===

function input_dispatcher:joystickadded(joystick)
    if self.input and self.input.joystickAdded then
        self.input:joystickAdded(joystick)
    end
end

function input_dispatcher:joystickremoved(joystick)
    if self.input and self.input.joystickRemoved then
        self.input:joystickRemoved(joystick)
    end
end

function input_dispatcher:gamepadpressed(joystick, button)
    if self.scene_control.current and self.scene_control.current.gamepadpressed then
        self.scene_control.current:gamepadpressed(joystick, button)
    end
end

function input_dispatcher:gamepadreleased(joystick, button)
    if self.scene_control.current and self.scene_control.current.gamepadreleased then
        self.scene_control.current:gamepadreleased(joystick, button)
    end
end

function input_dispatcher:gamepadaxis(joystick, axis, value)
    if self.scene_control.current and self.scene_control.current.gamepadaxis then
        self.scene_control.current:gamepadaxis(joystick, axis, value)
    end
end

return input_dispatcher

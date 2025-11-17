-- systems/input/sources/physical_gamepad_input.lua
-- Physical gamepad/controller input source

local base_input = require "engine.core.input.sources.base_input"
local constants = require "engine.core.constants"

local physical_gamepad_input = {}
setmetatable(physical_gamepad_input, { __index = base_input })
physical_gamepad_input.__index = physical_gamepad_input

function physical_gamepad_input:new(joystick, settings, input_config)
    local instance = setmetatable(base_input:new(), physical_gamepad_input)
    instance.name = "PhysicalGamepad"
    instance.priority = 80 -- High priority, but below virtual gamepad
    instance.joystick = joystick
    instance.settings = settings or {
        deadzone = constants.INPUT.GAMEPAD_DEADZONE,
        vibration_enabled = true,
        vibration_strength = 1.0
    }
    instance.input_config = input_config

    -- Track axis state for button-like behavior (menu navigation)
    instance.axis_state = {
        leftx = { value = 0, was_positive = false, was_negative = false },
        lefty = { value = 0, was_positive = false, was_negative = false }
    }
    instance.axis_threshold = 0.5 -- Threshold for axis to register as button press

    return instance
end

function physical_gamepad_input:isAvailable()
    return self.enabled and self.joystick ~= nil
end

function physical_gamepad_input:update(dt)
    if not self:isAvailable() then
        return
    end

    -- Update axis state for button-like detection
    for axis_name, state in pairs(self.axis_state) do
        local raw_value = self.joystick:getGamepadAxis(axis_name)
        local value = self:applyDeadzone(raw_value)

        -- Store previous state BEFORE updating value
        state.was_positive = (state.value > self.axis_threshold)
        state.was_negative = (state.value < -self.axis_threshold)

        -- Update current value
        state.value = value
    end
end

function physical_gamepad_input:applyDeadzone(value)
    if math.abs(value) < self.settings.deadzone then
        return 0
    end

    local sign = value > 0 and 1 or -1
    local adjusted = (math.abs(value) - self.settings.deadzone) / (1 - self.settings.deadzone)

    return sign * adjusted
end

function physical_gamepad_input:getMovement()
    if not self:isAvailable() then
        return 0, 0, false
    end

    local stick_x = self.joystick:getGamepadAxis("leftx")
    local stick_y = self.joystick:getGamepadAxis("lefty")

    stick_x = self:applyDeadzone(stick_x)
    stick_y = self:applyDeadzone(stick_y)

    if math.abs(stick_x) > constants.INPUT.STICK_THRESHOLD or
        math.abs(stick_y) > constants.INPUT.STICK_THRESHOLD then
        return stick_x, stick_y, true
    end

    return 0, 0, false
end

function physical_gamepad_input:getAimDirection(player_x, player_y, cam)
    if not self:isAvailable() then
        return 0, false
    end

    local stick_x = self.joystick:getGamepadAxis("rightx")
    local stick_y = self.joystick:getGamepadAxis("righty")

    stick_x = self:applyDeadzone(stick_x)
    stick_y = self:applyDeadzone(stick_y)

    if math.abs(stick_x) > constants.INPUT.AIM_STICK_THRESHOLD or
        math.abs(stick_y) > constants.INPUT.AIM_STICK_THRESHOLD then
        local angle = math.atan2(stick_y, stick_x)
        return angle, true
    end

    return 0, false
end

function physical_gamepad_input:isActionDown(action_mapping)
    if not self:isAvailable() then
        return false
    end

    -- Check gamepad button
    if action_mapping.gamepad then
        if self.joystick:isGamepadDown(action_mapping.gamepad) then
            return true
        end
    end

    -- Check D-pad
    if action_mapping.gamepad_dpad then
        if self.joystick:isGamepadDown("dp" .. action_mapping.gamepad_dpad) then
            return true
        end
    end

    -- Check axis (for menu navigation with stick)
    if action_mapping.gamepad_axis then
        local axis_name = action_mapping.gamepad_axis.axis
        local is_negative = action_mapping.gamepad_axis.negative

        if self.axis_state[axis_name] then
            local value = self.axis_state[axis_name].value
            if is_negative then
                return value < -self.axis_threshold
            else
                return value > self.axis_threshold
            end
        end
    end

    return false
end

function physical_gamepad_input:wasActionPressed(action_mapping, source, value)
    if not self:isAvailable() then
        return false
    end

    -- Handle button events
    if source == "gamepad" and value then
        if action_mapping.gamepad and action_mapping.gamepad == value then
            return true
        end

        if action_mapping.gamepad_dpad and ("dp" .. action_mapping.gamepad_dpad) == value then
            return true
        end
    end

    -- Check axis press (for menu navigation with stick)
    -- This is called from update loop, not from button events
    if action_mapping.gamepad_axis then
        local axis_name = action_mapping.gamepad_axis.axis
        local is_negative = action_mapping.gamepad_axis.negative

        if self.axis_state[axis_name] then
            local state = self.axis_state[axis_name]
            local current_value = state.value

            -- Detect axis crossing threshold (edge trigger)
            if is_negative then
                local is_pressed = (current_value < -self.axis_threshold)
                local was_pressed = state.was_negative
                return is_pressed and not was_pressed
            else
                local is_pressed = (current_value > self.axis_threshold)
                local was_pressed = state.was_positive
                return is_pressed and not was_pressed
            end
        end
    end

    return false
end

function physical_gamepad_input:vibrate(duration, left_strength, right_strength)
    if not self:isAvailable() or not self.settings.vibration_enabled then
        return
    end

    left_strength = (left_strength or 1.0) * self.settings.vibration_strength
    right_strength = (right_strength or left_strength) * self.settings.vibration_strength

    self.joystick:setVibration(left_strength, right_strength, duration)
end

function physical_gamepad_input:stopVibration()
    if self:isAvailable() then
        self.joystick:setVibration(0, 0)
    end
end

function physical_gamepad_input:getJoystickName()
    if self:isAvailable() then
        return self.joystick:getName()
    end
    return "No Controller"
end

function physical_gamepad_input:getDebugInfo()
    if not self:isAvailable() then
        return self.name .. ": Not connected"
    end

    local vx, vy, has_move = self:getMovement()
    local info = self.name .. ": " .. self:getJoystickName() .. "\n"
    info = info .. "  Buttons: " .. self.joystick:getButtonCount() .. "\n"
    info = info .. "  Left Stick: " .. string.format("(%.2f, %.2f)", vx, vy) .. "\n"

    local rx = self.joystick:getGamepadAxis("rightx")
    local ry = self.joystick:getGamepadAxis("righty")
    info = info .. "  Right Stick: " .. string.format("(%.2f, %.2f)", rx, ry) .. "\n"
    info = info .. "  Deadzone: " .. string.format("%.2f", self.settings.deadzone)

    return info
end

return physical_gamepad_input

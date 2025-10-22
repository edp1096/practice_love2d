-- systems/input.lua
-- Input system with Android virtual gamepad integration

local input_config = require "data.input_config"

local input = {}

input.joystick = nil
input.joystick_name = "No Controller"
input.settings = input_config.gamepad_settings

-- Last aim direction
input.last_aim_angle = 0
input.last_aim_source = "none"
input.actions = {}

-- Button repeat system
input.button_repeat = {
    delay = 0.3,
    interval = 0.1,
    timers = {}
}

-- Virtual gamepad reference (will be set from main.lua)
input.virtual_gamepad = nil

function input:init()
    for category, actions in pairs(input_config) do
        if type(actions) == "table" and category ~= "gamepad_settings" and category ~= "button_prompts" then
            for action_name, mapping in pairs(actions) do
                self.actions[action_name] = mapping
            end
        end
    end

    self:detectJoystick()
    print("Input system initialized")
    if self.joystick then
        print("  Controller: " .. self.joystick_name)
        print("  Buttons: " .. self.joystick:getButtonCount())
        print("  Axes: " .. self.joystick:getAxisCount())
    end
end

function input:setVirtualGamepad(vgp)
    self.virtual_gamepad = vgp
    print("Virtual gamepad linked to input system")
end

function input:detectJoystick()
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then
        self.joystick = joysticks[1]
        self.joystick_name = self.joystick:getName()
        return true
    else
        self.joystick = nil
        self.joystick_name = "No Controller"
        return false
    end
end

-- Joystick callbacks
function input:joystickAdded(joystick)
    if not self.joystick then
        self.joystick = joystick
        self.joystick_name = joystick:getName()
        print("Controller connected: " .. self.joystick_name)
    end
end

function input:joystickRemoved(joystick)
    if self.joystick == joystick then
        print("Controller disconnected: " .. self.joystick_name)
        self.joystick = nil
        self.joystick_name = "No Controller"
        self:detectJoystick()
    end
end

function input:update(dt)
    for action, timer in pairs(self.button_repeat.timers) do
        if timer.active then
            timer.time = timer.time + dt
            if timer.time >= (timer.initial and self.button_repeat.delay or self.button_repeat.interval) then
                timer.time = 0
                timer.initial = false
                timer.callback()
            end
        end
    end
end

function input:isDown(action)
    local mapping = self.actions[action]
    if not mapping then return false end

    -- Keyboard check
    if mapping.keyboard then
        for _, key in ipairs(mapping.keyboard) do
            if love.keyboard.isDown(key) then return true end
        end
    end

    -- Physical gamepad check
    if mapping.gamepad and self.joystick then
        if self.joystick:isGamepadDown(mapping.gamepad) then return true end
    end

    if mapping.gamepad_dpad and self.joystick then
        if self.joystick:isGamepadDown("dp" .. mapping.gamepad_dpad) then return true end
    end

    -- Virtual gamepad check
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        if mapping.gamepad_dpad then
            if self.virtual_gamepad:isDirectionPressed(mapping.gamepad_dpad) then
                return true
            end
        end
    end

    return false
end

function input:wasPressed(action, source, value)
    local mapping = self.actions[action]
    if not mapping then return false end

    if source == "keyboard" and mapping.keyboard then
        for _, key in ipairs(mapping.keyboard) do
            if key == value then return true end
        end
    end

    if source == "mouse" and mapping.mouse then
        if mapping.mouse == value then return true end
    end

    if source == "gamepad" and mapping.gamepad then
        if mapping.gamepad == value then return true end
    end

    if source == "gamepad" and mapping.gamepad_dpad then
        if "dp" .. mapping.gamepad_dpad == value then return true end
    end

    return false
end

function input:getMovement()
    local vx, vy = 0, 0

    -- Virtual gamepad check (highest priority on mobile)
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        local stick_x, stick_y = self.virtual_gamepad:getStickAxis()
        if math.abs(stick_x) > 0.01 or math.abs(stick_y) > 0.01 then
            return stick_x, stick_y
        end
    end

    -- Physical gamepad left stick
    if self.joystick then
        local stick_x = self.joystick:getGamepadAxis("leftx")
        local stick_y = self.joystick:getGamepadAxis("lefty")

        stick_x = self:applyDeadzone(stick_x)
        stick_y = self:applyDeadzone(stick_y)

        if math.abs(stick_x) > 0.01 or math.abs(stick_y) > 0.01 then
            return stick_x, stick_y
        end
    end

    -- Keyboard
    if self:isDown("move_right") then vx = vx + 1 end
    if self:isDown("move_left") then vx = vx - 1 end
    if self:isDown("move_down") then vy = vy + 1 end
    if self:isDown("move_up") then vy = vy - 1 end

    -- Normalize diagonal movement
    if vx ~= 0 and vy ~= 0 then
        local length = math.sqrt(vx * vx + vy * vy)
        vx = vx / length
        vy = vy / length
    end

    return vx, vy
end

function input:getAimDirection(player_x, player_y, cam)
    local has_gamepad_input = false

    -- Physical gamepad right stick
    if self.joystick then
        local stick_x = self.joystick:getGamepadAxis("rightx")
        local stick_y = self.joystick:getGamepadAxis("righty")
        stick_x = self:applyDeadzone(stick_x)
        stick_y = self:applyDeadzone(stick_y)

        if math.abs(stick_x) > 0.1 or math.abs(stick_y) > 0.1 then
            self.last_aim_angle = math.atan2(stick_y, stick_x)
            self.last_aim_source = "gamepad"
            has_gamepad_input = true
            return self.last_aim_angle
        end
    end

    -- Mouse aiming (or touch position when weapon is drawn)
    local mouse_x, mouse_y
    if cam then
        mouse_x, mouse_y = cam:worldCoords(love.mouse.getPosition())
    else
        mouse_x, mouse_y = love.mouse.getPosition()
    end

    local mouse_angle = math.atan2(mouse_y - player_y, mouse_x - player_x)

    -- Check if mouse moved significantly
    local angle_diff = math.abs(mouse_angle - (self.last_aim_angle or 0))
    if angle_diff > math.pi then angle_diff = 2 * math.pi - angle_diff end

    if angle_diff > 0.087 then self.last_aim_source = "mouse" end

    -- Use mouse angle if active
    if self.last_aim_source ~= "gamepad" or not has_gamepad_input then
        self.last_aim_angle = mouse_angle
        self.last_aim_source = "mouse"

        return self.last_aim_angle
    end

    return self.last_aim_angle
end

function input:resetAimSource() self.last_aim_source = "none" end

-- Apply deadzone to analog value of gamepad
function input:applyDeadzone(value)
    if math.abs(value) < self.settings.deadzone then return 0 end

    local sign = value > 0 and 1 or -1
    local adjusted = (math.abs(value) - self.settings.deadzone) / (1 - self.settings.deadzone)

    return sign * adjusted
end

-- Vibration (haptic feedback)
function input:vibrate(duration, left_strength, right_strength)
    if not self.settings.vibration_enabled or not self.joystick then return end

    left_strength = (left_strength or 1.0) * self.settings.vibration_strength
    right_strength = (right_strength or left_strength) * self.settings.vibration_strength

    self.joystick:setVibration(left_strength, right_strength, duration)
end

-- Preset vibration patterns
function input:vibrateAttack() self:vibrate(0.1, 0.5, 0.5) end

function input:vibrateParry() self:vibrate(0.15, 0.8, 0.8) end

function input:vibratePerfectParry() self:vibrate(0.3, 1.0, 1.0) end

function input:vibrateHit() self:vibrate(0.2, 0.8, 0.3) end

function input:vibrateDodge() self:vibrate(0.08, 0.4, 0.4) end

function input:vibrateWeaponHit() self:vibrate(0.15, 0.7, 0.7) end

function input:setDeadzone(value) self.settings.deadzone = math.max(0, math.min(1, value)) end

function input:setVibrationEnabled(enabled)
    self.settings.vibration_enabled = enabled
    if not enabled and self.joystick then self.joystick:setVibration(0, 0) end
end

function input:setVibrationStrength(strength)
    self.settings.vibration_strength = math.max(0, math.min(1, strength))
end

-- Check if gamepad is connected (physical or virtual)
function input:hasGamepad()
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        return true
    end
    return self.joystick ~= nil
end

-- Get button prompt string (for UI)
function input:getPrompt(action)
    local mapping = self.actions[action]
    if not mapping then return "?" end

    -- If virtual gamepad is active, show mobile-friendly prompts
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        if action == "attack" then
            return "[A]"
        elseif action == "dodge" then
            return "[B]"
        elseif action == "parry" then
            return "[X]"
        elseif action == "interact" then
            return "[Y]"
        elseif action == "pause" then
            return "[☰]"
        end
    end

    if self.joystick and mapping.gamepad then
        return input_config.button_prompts[mapping.gamepad] or ("[" .. mapping.gamepad .. "]")
    elseif self.joystick and mapping.gamepad_dpad then
        return "[D-Pad " .. mapping.gamepad_dpad:upper() .. "]"
    elseif mapping.keyboard then
        return "[" .. mapping.keyboard[1]:upper() .. "]"
    elseif mapping.mouse then
        return mapping.mouse == 1 and input_config.button_prompts.mouse_1 or input_config.button_prompts.mouse_2
    end

    return "?"
end

function input:getDebugInfo()
    local info = ""

    -- Virtual gamepad status
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        info = info .. "Virtual Gamepad: ENABLED\n"
        local vx, vy = self.virtual_gamepad:getStickAxis()
        info = info .. "Virtual Stick: " .. string.format("%.2f, %.2f", vx, vy) .. "\n"
        info = info .. "\n"
    end

    -- Physical controller status
    if not self.joystick then
        info = info .. "Physical Controller: Not connected"
        return info
    end

    info = info .. "Controller: " .. self.joystick_name .. "\n"
    info = info .. "Buttons: " .. self.joystick:getButtonCount() .. "\n"
    info = info .. "Axes: " .. self.joystick:getAxisCount() .. "\n"
    info = info .. "Deadzone: " .. string.format("%.2f", self.settings.deadzone) .. "\n"
    info = info .. "Vibration: " .. (self.settings.vibration_enabled and "ON" or "OFF") .. "\n"
    info = info .. "Strength: " .. string.format("%.0f%%", self.settings.vibration_strength * 100) .. "\n"
    info = info .. "\nLeft Stick: " .. string.format("%.2f, %.2f",
        self.joystick:getGamepadAxis("leftx"),
        self.joystick:getGamepadAxis("lefty")) .. "\n"
    info = info .. "Right Stick: " .. string.format("%.2f, %.2f",
        self.joystick:getGamepadAxis("rightx"),
        self.joystick:getGamepadAxis("righty")) .. "\n"
    info = info .. "Aim Source: " .. self.last_aim_source

    return info
end

input:init()

return input

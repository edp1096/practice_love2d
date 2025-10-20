-- systems/input.lua
-- Unified input system: keyboard, mouse, gamepad support with DualSense optimization

local input = {}

-- Active joystick
input.joystick = nil
input.joystick_name = "No Controller"

-- Gamepad settings
input.settings = {
    deadzone = 0.15,
    vibration_enabled = true,
    vibration_strength = 1.0
}

-- Last aim direction (for maintaining direction when stick is released)
input.last_aim_angle = 0
input.last_aim_source = "none" -- "gamepad", "mouse", "initial", or "none"

-- Action mappings
input.actions = {
    -- Movement (analog or digital)
    move_left = { keyboard = { "a", "left" }, gamepad_axis = { axis = "leftx", negative = true } },
    move_right = { keyboard = { "d", "right" }, gamepad_axis = { axis = "leftx", negative = false } },
    move_up = { keyboard = { "w", "up" }, gamepad_axis = { axis = "lefty", negative = true } },
    move_down = { keyboard = { "s", "down" }, gamepad_axis = { axis = "lefty", negative = false } },

    -- Aim (analog stick)
    aim = { gamepad_axis = { axis = "rightx", axis2 = "righty" } },

    -- Combat actions
    attack = { mouse = 1, gamepad = "a" },             -- Cross button on DualSense
    parry = { mouse = 2, gamepad = "x" },              -- Square button on DualSense
    dodge = { keyboard = { "space" }, gamepad = "b" }, -- Circle button on DualSense
    interact = { keyboard = { "f" }, gamepad = "y" },  -- Triangle button on DualSense

    -- Menu navigation
    menu_up = { keyboard = { "w", "up" }, gamepad_dpad = "up" },
    menu_down = { keyboard = { "s", "down" }, gamepad_dpad = "down" },
    menu_left = { keyboard = { "a", "left" }, gamepad_dpad = "left" },
    menu_right = { keyboard = { "d", "right" }, gamepad_dpad = "right" },
    menu_select = { keyboard = { "return", "space" }, gamepad = "a" },
    menu_back = { keyboard = { "escape" }, gamepad = "b" },

    -- Pause
    pause = { keyboard = { "p", "escape" }, gamepad = "start" },

    -- Quick save (F1-F3 or L1/R1)
    quicksave_1 = { keyboard = { "f1" }, gamepad = "leftshoulder" },
    quicksave_2 = { keyboard = { "f2" }, gamepad = "rightshoulder" },
    quicksave_3 = { keyboard = { "f3" } }
}

-- Button repeat system for menu navigation
input.button_repeat = {
    delay = 0.3,
    interval = 0.1,
    timers = {}
}

-- Initialize input system
function input:init()
    self:detectJoystick()
    print("Input system initialized")
    if self.joystick then
        print("  Controller: " .. self.joystick_name)
        print("  Buttons: " .. self.joystick:getButtonCount())
        print("  Axes: " .. self.joystick:getAxisCount())
    end
end

-- Detect and connect joystick
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

-- Joystick connected callback
function input:joystickAdded(joystick)
    if not self.joystick then
        self.joystick = joystick
        self.joystick_name = joystick:getName()
        print("Controller connected: " .. self.joystick_name)
    end
end

-- Joystick disconnected callback
function input:joystickRemoved(joystick)
    if self.joystick == joystick then
        print("Controller disconnected: " .. self.joystick_name)
        self.joystick = nil
        self.joystick_name = "No Controller"
        self:detectJoystick()
    end
end

-- Update (for button repeat)
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

-- Check if action is currently pressed
function input:isDown(action)
    local mapping = self.actions[action]
    if not mapping then return false end

    -- Keyboard
    if mapping.keyboard then
        for _, key in ipairs(mapping.keyboard) do
            if love.keyboard.isDown(key) then
                return true
            end
        end
    end

    -- Gamepad button
    if mapping.gamepad and self.joystick then
        if self.joystick:isGamepadDown(mapping.gamepad) then
            return true
        end
    end

    -- Gamepad D-Pad
    if mapping.gamepad_dpad and self.joystick then
        if self.joystick:isGamepadDown("dp" .. mapping.gamepad_dpad) then
            return true
        end
    end

    return false
end

-- Check if action was just pressed (use in keypressed/gamepadpressed)
function input:wasPressed(action, source, value)
    local mapping = self.actions[action]
    if not mapping then return false end

    -- Keyboard
    if source == "keyboard" and mapping.keyboard then
        for _, key in ipairs(mapping.keyboard) do
            if key == value then
                return true
            end
        end
    end

    -- Mouse button
    if source == "mouse" and mapping.mouse then
        if mapping.mouse == value then
            return true
        end
    end

    -- Gamepad button
    if source == "gamepad" and mapping.gamepad then
        if mapping.gamepad == value then
            return true
        end
    end

    -- Gamepad D-Pad
    if source == "gamepad" and mapping.gamepad_dpad then
        if "dp" .. mapping.gamepad_dpad == value then
            return true
        end
    end

    return false
end

-- Get analog stick value for action
function input:getAxis(action)
    local mapping = self.actions[action]
    if not mapping or not mapping.gamepad_axis or not self.joystick then
        return 0, 0
    end

    local axis_mapping = mapping.gamepad_axis

    -- Single axis (e.g., move_left/move_right)
    if axis_mapping.axis and not axis_mapping.axis2 then
        local value = self.joystick:getGamepadAxis(axis_mapping.axis)
        value = self:applyDeadzone(value)

        if axis_mapping.negative then
            return -math.min(0, value), 0
        else
            return math.max(0, value), 0
        end
    end

    -- Dual axis (e.g., aim with right stick)
    if axis_mapping.axis and axis_mapping.axis2 then
        local x = self.joystick:getGamepadAxis(axis_mapping.axis)
        local y = self.joystick:getGamepadAxis(axis_mapping.axis2)

        x = self:applyDeadzone(x)
        y = self:applyDeadzone(y)

        return x, y
    end

    return 0, 0
end

-- Get movement vector from keyboard or gamepad
function input:getMovement()
    local vx, vy = 0, 0

    -- Gamepad left stick (priority)
    if self.joystick then
        local stick_x = self.joystick:getGamepadAxis("leftx")
        local stick_y = self.joystick:getGamepadAxis("lefty")

        stick_x = self:applyDeadzone(stick_x)
        stick_y = self:applyDeadzone(stick_y)

        if math.abs(stick_x) > 0.01 or math.abs(stick_y) > 0.01 then
            return stick_x, stick_y
        end
    end

    -- Keyboard (fallback)
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

-- Get aim direction from mouse or gamepad right stick
function input:getAimDirection(player_x, player_y, cam)
    -- Gamepad right stick (priority)
    if self.joystick then
        local stick_x = self.joystick:getGamepadAxis("rightx")
        local stick_y = self.joystick:getGamepadAxis("righty")

        stick_x = self:applyDeadzone(stick_x)
        stick_y = self:applyDeadzone(stick_y)

        if math.abs(stick_x) > 0.1 or math.abs(stick_y) > 0.1 then
            -- Active gamepad aim input - update and remember
            self.last_aim_angle = math.atan2(stick_y, stick_x)
            self.last_aim_source = "gamepad"
            return self.last_aim_angle
        end
    end

    -- If we had gamepad input before and now stick is released, maintain last direction
    if self.last_aim_source == "gamepad" then
        return self.last_aim_angle
    end

    -- If weapon was just drawn (initial), maintain that direction until player aims
    if self.last_aim_source == "initial" then
        return self.last_aim_angle
    end

    -- Mouse (fallback) - only used if gamepad was never used
    local mouse_x, mouse_y
    if cam then
        mouse_x, mouse_y = cam:worldCoords(love.mouse.getPosition())
    else
        mouse_x, mouse_y = love.mouse.getPosition()
    end

    self.last_aim_angle = math.atan2(mouse_y - player_y, mouse_x - player_x)
    self.last_aim_source = "mouse"
    return self.last_aim_angle
end

-- Reset aim source when weapon is sheathed
function input:resetAimSource()
    self.last_aim_source = "none"
end

-- Apply deadzone to analog value
function input:applyDeadzone(value)
    if math.abs(value) < self.settings.deadzone then
        return 0
    end

    -- Smooth deadzone transition
    local sign = value > 0 and 1 or -1
    local adjusted = (math.abs(value) - self.settings.deadzone) / (1 - self.settings.deadzone)
    return sign * adjusted
end

-- Vibration (haptic feedback)
function input:vibrate(duration, left_strength, right_strength)
    if not self.settings.vibration_enabled or not self.joystick then
        return
    end

    left_strength = (left_strength or 1.0) * self.settings.vibration_strength
    right_strength = (right_strength or left_strength) * self.settings.vibration_strength

    self.joystick:setVibration(left_strength, right_strength, duration)
end

-- Preset vibration patterns
function input:vibrateAttack()
    self:vibrate(0.1, 0.5, 0.5)
end

function input:vibrateParry()
    self:vibrate(0.15, 0.8, 0.8)
end

function input:vibratePerfectParry()
    self:vibrate(0.3, 1.0, 1.0)
end

function input:vibrateHit()
    self:vibrate(0.2, 0.8, 0.3)
end

function input:vibrateDodge()
    self:vibrate(0.08, 0.4, 0.4)
end

function input:vibrateWeaponHit()
    self:vibrate(0.15, 0.7, 0.7)
end

-- Button repeat for menu navigation
function input:startRepeat(action, callback)
    if not self.button_repeat.timers[action] then
        self.button_repeat.timers[action] = {
            active = false,
            time = 0,
            initial = true,
            callback = nil
        }
    end

    local timer = self.button_repeat.timers[action]
    timer.active = true
    timer.time = 0
    timer.initial = true
    timer.callback = callback
end

function input:stopRepeat(action)
    if self.button_repeat.timers[action] then
        self.button_repeat.timers[action].active = false
    end
end

function input:stopAllRepeats()
    for action, timer in pairs(self.button_repeat.timers) do
        timer.active = false
    end
end

-- Settings
function input:setDeadzone(value)
    self.settings.deadzone = math.max(0, math.min(1, value))
end

function input:setVibrationEnabled(enabled)
    self.settings.vibration_enabled = enabled
    if not enabled and self.joystick then
        self.joystick:setVibration(0, 0)
    end
end

function input:setVibrationStrength(strength)
    self.settings.vibration_strength = math.max(0, math.min(1, strength))
end

-- Check if gamepad is connected
function input:hasGamepad()
    return self.joystick ~= nil
end

-- Get button prompt string (for UI)
function input:getPrompt(action)
    local mapping = self.actions[action]
    if not mapping then return "?" end

    if self.joystick and mapping.gamepad then
        -- DualSense button names
        local button_names = {
            a = "[✕]", -- Cross
            b = "[○]", -- Circle
            x = "[□]", -- Square
            y = "[△]", -- Triangle
            leftshoulder = "[L1]",
            rightshoulder = "[R1]",
            start = "[Options]",
            back = "[Share]"
        }
        return button_names[mapping.gamepad] or "[" .. mapping.gamepad .. "]"
    elseif self.joystick and mapping.gamepad_dpad then
        return "[D-Pad " .. mapping.gamepad_dpad:upper() .. "]"
    elseif mapping.keyboard then
        return "[" .. mapping.keyboard[1]:upper() .. "]"
    elseif mapping.mouse then
        return mapping.mouse == 1 and "[LMB]" or "[RMB]"
    end

    return "?"
end

-- Debug info
function input:getDebugInfo()
    if not self.joystick then
        return "No controller connected"
    end

    local info = "Controller: " .. self.joystick_name .. "\n"
    info = info .. "Buttons: " .. self.joystick:getButtonCount() .. "\n"
    info = info .. "Axes: " .. self.joystick:getAxisCount() .. "\n"
    info = info .. "Deadzone: " .. string.format("%.2f", self.settings.deadzone) .. "\n"
    info = info .. "Vibration: " .. (self.settings.vibration_enabled and "ON" or "OFF") .. "\n"
    info = info .. "Strength: " .. string.format("%.0f%%", self.settings.vibration_strength * 100) .. "\n"
    info = info .. "\n"
    info = info .. "Left Stick: " .. string.format("%.2f, %.2f",
        self.joystick:getGamepadAxis("leftx"),
        self.joystick:getGamepadAxis("lefty")) .. "\n"
    info = info .. "Right Stick: " .. string.format("%.2f, %.2f",
        self.joystick:getGamepadAxis("rightx"),
        self.joystick:getGamepadAxis("righty")) .. "\n"
    info = info .. "Aim Source: " .. self.last_aim_source

    return info
end

-- Initialize on load
input:init()

return input

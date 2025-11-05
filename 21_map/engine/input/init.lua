-- systems/input.lua
-- Wrapper for input_coordinator with backward compatibility

local input_config = require "game.data.input_config"
local constants = require "engine.constants"

local input = {}

-- Core components
input.coordinator = nil
input.joystick = nil
input.joystick_name = "No Controller"
input.settings = input_config.gamepad_settings

-- Button repeat system
input.button_repeat = {
    delay = constants.INPUT.REPEAT_DELAY,
    interval = constants.INPUT.REPEAT_INTERVAL,
    timers = {}
}

input.virtual_gamepad = nil

-- Get action mapping from config
local function getActionMapping(action_name)
    for category, actions in pairs(input_config) do
        if type(actions) == "table" and category ~= "gamepad_settings" and category ~= "button_prompts" then
            if actions[action_name] then
                return actions[action_name]
            end
        end
    end
    return nil
end

-- Initialize input system
function input:init()
    self:detectJoystick()

    -- Initialize coordinator
    local input_coordinator = require "engine.input.input_coordinator"
    self.coordinator = input_coordinator
    input_coordinator:init(self.joystick, self.virtual_gamepad, self.settings)

    print("Input system initialized")
    if self.joystick then
        print("  Controller: " .. self.joystick_name)
        print("  Buttons: " .. self.joystick:getButtonCount())
        print("  Axes: " .. self.joystick:getAxisCount())
    end
end

function input:setVirtualGamepad(vgp)
    self.virtual_gamepad = vgp
    if self.coordinator then
        self.coordinator:setVirtualGamepad(vgp)
    end
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

        if self.coordinator then
            self.coordinator:setJoystick(joystick, self.settings)
        end
    end
end

function input:joystickRemoved(joystick)
    if self.joystick == joystick then
        print("Controller disconnected: " .. self.joystick_name)
        self.joystick = nil
        self.joystick_name = "No Controller"

        if self.coordinator then
            self.coordinator:setJoystick(nil)
        end
    end
end

function input:update(dt)
    -- Update button repeat timers
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

    -- Update coordinator
    if self.coordinator then
        self.coordinator:update(dt)
    end
end

-- Action queries (delegate to coordinator)
function input:isDown(action)
    local mapping = getActionMapping(action)
    if not mapping then return false end
    return self.coordinator:isActionDown(mapping)
end

function input:wasPressed(action, source, value)
    local mapping = getActionMapping(action)
    if not mapping then return false end
    return self.coordinator:wasActionPressed(mapping, source, value)
end

function input:getMovement()
    return self.coordinator:getMovement()
end

function input:getAimDirection(player_x, player_y, cam)
    return self.coordinator:getAimDirection(player_x, player_y, cam)
end

function input:resetAimSource()
    if self.coordinator then
        self.coordinator:resetAimSource()
    end
end

function input:setAimAngle(angle, source)
    if self.coordinator then
        self.coordinator:setAimAngle(angle, source)
    end
end

-- Set game context for context-based actions
function input:setGameContext(context)
    if self.coordinator then
        self.coordinator:setGameContext(context)
    end
end

-- Handle gamepad button pressed event
function input:handleGamepadPressed(joystick, button)
    if self.coordinator then
        return self.coordinator:handleGamepadPressed(joystick, button)
    end
    return nil
end

-- Handle gamepad axis event (for triggers on Xbox controllers)
function input:handleGamepadAxis(joystick, axis, value)
    if self.coordinator then
        return self.coordinator:handleGamepadAxis(joystick, axis, value)
    end
    return nil
end

-- Vibration
function input:vibrate(duration, left_strength, right_strength)
    if self.coordinator then
        self.coordinator:vibrate(duration, left_strength, right_strength)
    end
end

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

function input:setMobileVibrationEnabled(enabled)
    self.settings.mobile_vibration_enabled = enabled
end

-- Queries
function input:hasGamepad()
    if self.coordinator then
        return self.coordinator:hasGamepad()
    end

    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        return true
    end
    return self.joystick ~= nil
end

function input:getPrompt(action)
    local mapping = getActionMapping(action)
    if not mapping then return "?" end

    -- Virtual gamepad prompts
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
            return "[START]"
        end
    end

    -- Physical gamepad prompts
    if self.joystick then
        if mapping.gamepad then
            return "[" .. mapping.gamepad:upper() .. "]"
        end
    end

    -- Keyboard prompts
    if mapping.keyboard and #mapping.keyboard > 0 then
        return "[" .. mapping.keyboard[1]:upper() .. "]"
    end

    return "?"
end

function input:getDebugInfo()
    local info = "Input System:\n"
    info = info .. "  Joystick: " .. self.joystick_name .. "\n"
    info = info .. "  Deadzone: " .. string.format("%.2f", self.settings.deadzone) .. "\n"
    info = info .. "  Vibration: " .. tostring(self.settings.vibration_enabled) .. "\n"
    info = info .. "  Last Aim: " .. self.last_aim_source .. "\n"

    if self.coordinator then
        info = info .. "  Coordinator: Active\n"
    end

    return info
end

return input

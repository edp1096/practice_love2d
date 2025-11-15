-- systems/input.lua
-- Wrapper for input_mapper with backward compatibility

local constants = require "engine.core.constants"

local input = {}

-- Core components
input.mapper = nil
input.joystick = nil
input.joystick_name = "No Controller"
input.settings = {
    deadzone = 0.15,
    vibration_enabled = true,
    vibration_strength = 1.0,
    mobile_vibration_enabled = true
}
input.input_config = nil  -- Store injected input config

-- Button repeat system
input.button_repeat = {
    delay = constants.INPUT.REPEAT_DELAY,
    interval = constants.INPUT.REPEAT_INTERVAL,
    timers = {}
}

input.virtual_gamepad = nil

-- Get action mapping from config
local function getActionMapping(action_name)
    if not input.input_config then return nil end

    for category, actions in pairs(input.input_config) do
        if type(actions) == "table" and category ~= "gamepad_settings" and category ~= "button_prompts" then
            if actions[action_name] then
                return actions[action_name]
            end
        end
    end
    return nil
end

-- Initialize input system
function input:init(input_config)
    if not input_config then
        print("Warning: No input config provided to input:init()")
        return
    end

    -- Store input config
    self.input_config = input_config

    -- Load gamepad settings from config
    if input_config.gamepad_settings then
        self.settings.deadzone = input_config.gamepad_settings.deadzone or self.settings.deadzone
        self.settings.vibration_enabled = input_config.gamepad_settings.vibration_enabled
        self.settings.vibration_strength = input_config.gamepad_settings.vibration_strength or self.settings.vibration_strength
        self.settings.mobile_vibration_enabled = input_config.gamepad_settings.mobile_vibration_enabled
    end

    -- Override with APP_CONFIG if available
    if APP_CONFIG and APP_CONFIG.input then
        self.settings.deadzone = APP_CONFIG.input.deadzone
        self.settings.vibration_enabled = APP_CONFIG.input.vibration_enabled
        self.settings.vibration_strength = APP_CONFIG.input.vibration_strength
        self.settings.mobile_vibration_enabled = APP_CONFIG.input.mobile_vibration_enabled
    end

    self:detectJoystick()

    -- Initialize coordinator
    local input_mapper = require "engine.core.input.input_mapper"
    self.mapper = input_mapper
    input_mapper:init(self.joystick, self.virtual_gamepad, self.settings, input_config)
end

function input:setVirtualGamepad(vgp)
    self.virtual_gamepad = vgp
    if self.mapper then
        self.mapper:setVirtualPad(vgp)
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

        if self.mapper then
            self.mapper:setJoystick(joystick, self.settings)
        end
    end
end

function input:joystickRemoved(joystick)
    if self.joystick == joystick then
        self.joystick = nil
        self.joystick_name = "No Controller"

        if self.mapper then
            self.mapper:setJoystick(nil)
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
    if self.mapper then
        self.mapper:update(dt)
    end
end

-- Action queries (delegate to coordinator)
function input:isDown(action)
    local mapping = getActionMapping(action)
    if not mapping then return false end
    return self.mapper:isActionDown(mapping)
end

function input:wasPressed(action, source, value)
    local mapping = getActionMapping(action)
    if not mapping then return false end
    return self.mapper:wasActionPressed(mapping, source, value)
end

function input:getMovement()
    return self.mapper:getMovement()
end

function input:getAimDirection(player_x, player_y, cam)
    return self.mapper:getAimDirection(player_x, player_y, cam)
end

function input:resetAimSource()
    if self.mapper then
        self.mapper:resetAimSource()
    end
end

function input:setAimAngle(angle, source)
    if self.mapper then
        self.mapper:setAimAngle(angle, source)
    end
end

-- Set game context for context-based actions
function input:setGameContext(context)
    if self.mapper then
        self.mapper:setGameContext(context)
    end
end

-- Handle gamepad button pressed event
function input:handleGamepadPressed(joystick, button)
    if self.mapper then
        return self.mapper:handleGamepadPressed(joystick, button)
    end
    return nil
end

-- Handle gamepad axis event (for triggers on Xbox controllers)
function input:handleGamepadAxis(joystick, axis, value)
    if self.mapper then
        return self.mapper:handleGamepadAxis(joystick, axis, value)
    end
    return nil
end

-- Vibration
function input:vibrate(duration, left_strength, right_strength)
    if self.mapper then
        self.mapper:vibrate(duration, left_strength, right_strength)
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
    if self.mapper then
        return self.mapper:hasGamepad()
    end

    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        return true
    end
    return self.joystick ~= nil
end

-- Helper function to convert gamepad button names to readable format
local function formatGamepadButton(button)
    local button_names = {
        -- Shoulder buttons
        leftshoulder = "L1",
        rightshoulder = "R1",
        lefttrigger = "L2",
        righttrigger = "R2",

        -- Face buttons
        a = "A",
        b = "B",
        x = "X",
        y = "Y",

        -- D-pad
        dpup = "D-Up",
        dpdown = "D-Down",
        dpleft = "D-Left",
        dpright = "D-Right",

        -- System buttons
        start = "START",
        back = "SELECT",
        guide = "HOME",

        -- Stick buttons
        leftstick = "L3",
        rightstick = "R3"
    }

    return button_names[button:lower()] or button:upper()
end

function input:getPrompt(action)
    local mapping = getActionMapping(action)
    if not mapping then return "?" end

    -- Virtual gamepad prompts
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        if action == "attack" then
            return "A"
        elseif action == "dodge" then
            return "B"
        elseif action == "parry" then
            return "X"
        elseif action == "interact" then
            return "Y"
        elseif action == "pause" then
            return "START"
        elseif action == "use_item" then
            return "L1"
        elseif action == "menu_select" then
            return "A"
        elseif action == "open_inventory" then
            return "R2"
        elseif action == "menu_back" then
            return "B"
        end
    end

    -- Physical gamepad prompts
    if self.joystick then
        if mapping.gamepad then
            return formatGamepadButton(mapping.gamepad)
        end
    end

    -- Keyboard prompts
    if mapping.keyboard and #mapping.keyboard > 0 then
        local key = mapping.keyboard[1]:lower()

        -- Shorten long key names
        local key_names = {
            escape = "ESC",
            ["return"] = "ENTER",
            space = "SPACE",
            lshift = "SHIFT",
            rshift = "SHIFT",
            lctrl = "CTRL",
            rctrl = "CTRL",
            lalt = "ALT",
            ralt = "ALT"
        }

        return key_names[key] or mapping.keyboard[1]:upper()
    end

    return "?"
end

function input:getDebugInfo()
    local info = "Input System:\n"
    info = info .. "  Joystick: " .. self.joystick_name .. "\n"
    info = info .. "  Deadzone: " .. string.format("%.2f", self.settings.deadzone) .. "\n"
    info = info .. "  Vibration: " .. tostring(self.settings.vibration_enabled) .. "\n"

    if self.mapper then
        info = info .. "  Coordinator: Active\n"
    end

    return info
end

return input

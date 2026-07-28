local util = require "engine.core.util"

local Input = {}
Input.__index = Input

local function asSet(values)
    local result = {}
    for _, value in ipairs(values or {}) do
        result[value] = true
    end
    return result
end

function Input.new(bindings)
    local self = setmetatable({
        bindings = {},
        keys_down = {},
        buttons_down = {},
        axes = {},
        pressed = {},
        released = {},
        virtual = {},
    }, Input)

    for action, definition in pairs(bindings or {}) do
        self.bindings[action] = {
            keys = asSet(definition.keys),
            buttons = asSet(definition.buttons),
        }
    end
    return self
end

function Input:hasAction(action)
    return self.bindings[action] ~= nil
end

function Input:_actionsFor(device, value)
    local field = device == "key" and "keys" or "buttons"
    local result = {}
    for action, binding in pairs(self.bindings) do
        if binding[field][value] then
            result[#result + 1] = action
        end
    end
    return result
end

function Input:keypressed(key)
    if self.keys_down[key] then return end
    self.keys_down[key] = true
    for _, action in ipairs(self:_actionsFor("key", key)) do
        self.pressed[action] = true
    end
end

function Input:keyreleased(key)
    if not self.keys_down[key] then return end
    self.keys_down[key] = nil
    for _, action in ipairs(self:_actionsFor("key", key)) do
        self.released[action] = true
    end
end

function Input:gamepadpressed(button)
    if self.buttons_down[button] then return end
    self.buttons_down[button] = true
    for _, action in ipairs(self:_actionsFor("button", button)) do
        self.pressed[action] = true
    end
end

function Input:gamepadreleased(button)
    if not self.buttons_down[button] then return end
    self.buttons_down[button] = nil
    for _, action in ipairs(self:_actionsFor("button", button)) do
        self.released[action] = true
    end
end

function Input:gamepadaxis(axis, value)
    self.axes[axis] = util.clamp(value, -1, 1)
end

function Input:setAction(action, value, frames)
    assert(self.bindings[action], "unknown input action: " .. tostring(action))
    value = util.clamp(tonumber(value) or 0, 0, 1)
    frames = math.max(1, math.floor(tonumber(frames) or 1))

    if value > 0 then
        if not self:isDown(action) then self.pressed[action] = true end
        self.virtual[action] = {value = value, frames = frames}
    else
        if self:isDown(action) then self.released[action] = true end
        self.virtual[action] = nil
    end
end

function Input:value(action)
    local virtual = self.virtual[action]
    local value = virtual and virtual.value or 0
    local binding = self.bindings[action]
    if not binding then return value end

    for key in pairs(binding.keys) do
        if self.keys_down[key] then return 1 end
    end
    for button in pairs(binding.buttons) do
        if self.buttons_down[button] then return 1 end
    end
    return value
end

function Input:isDown(action)
    return self:value(action) > 0
end

function Input:wasPressed(action)
    return self.pressed[action] == true
end

function Input:consumePressed(action)
    local pressed = self.pressed[action] == true
    self.pressed[action] = nil
    return pressed
end

function Input:wasReleased(action)
    return self.released[action] == true
end

function Input:axis(negative_action, positive_action, joystick_axis, deadzone)
    local digital =
        self:value(positive_action) - self:value(negative_action)
    local analog = self.axes[joystick_axis or ""] or 0
    if math.abs(analog) < (deadzone or 0.2) then analog = 0 end
    return util.clamp(digital + analog, -1, 1)
end

function Input:endFrame()
    self.pressed = {}
    self.released = {}

    for action, state in pairs(self.virtual) do
        state.frames = state.frames - 1
        if state.frames <= 0 then
            self.virtual[action] = nil
            self.released[action] = true
        end
    end
end

return Input

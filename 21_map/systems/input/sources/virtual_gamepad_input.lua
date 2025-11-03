-- systems/input/sources/virtual_gamepad_input.lua
-- Virtual gamepad input source (for mobile devices)

local base_input = require "systems.input.sources.base_input"
local constants = require "systems.constants"

local virtual_gamepad_input = {}
setmetatable(virtual_gamepad_input, { __index = base_input })
virtual_gamepad_input.__index = virtual_gamepad_input

function virtual_gamepad_input:new(virtual_gamepad)
    local instance = setmetatable(base_input:new(), virtual_gamepad_input)
    instance.name = "VirtualGamepad"
    instance.priority = 100 -- Highest priority on mobile
    instance.virtual_gamepad = virtual_gamepad
    return instance
end

function virtual_gamepad_input:isAvailable()
    return self.enabled and self.virtual_gamepad and self.virtual_gamepad.enabled
end

function virtual_gamepad_input:getMovement()
    if not self:isAvailable() then
        return 0, 0, false
    end

    local stick_x, stick_y = self.virtual_gamepad:getStickAxis()

    -- Check if there's actual input
    if math.abs(stick_x) > constants.INPUT.STICK_THRESHOLD or
        math.abs(stick_y) > constants.INPUT.STICK_THRESHOLD then
        return stick_x, stick_y, true
    end

    return 0, 0, false
end

function virtual_gamepad_input:getAimDirection(player_x, player_y, cam)
    if not self:isAvailable() then
        return 0, false
    end

    local aim_angle, has_aim = self.virtual_gamepad:getAimDirection(player_x, player_y, cam)

    if has_aim and aim_angle then
        return aim_angle, true
    end

    return 0, false
end

function virtual_gamepad_input:isActionDown(action)
    if not self:isAvailable() then
        return false
    end

    -- Map actions to virtual gamepad directions
    if action == "move_up" or action == "move_down" or
        action == "move_left" or action == "move_right" then
        local direction_map = {
            move_up = "up",
            move_down = "down",
            move_left = "left",
            move_right = "right"
        }

        local direction = direction_map[action]
        if direction then
            return self.virtual_gamepad:isDirectionPressed(direction)
        end
    end

    return false
end

function virtual_gamepad_input:hasActiveTouches()
    if not self:isAvailable() then
        return false
    end

    return self.virtual_gamepad:hasActiveTouches()
end

function virtual_gamepad_input:isInPadArea(x, y)
    if not self:isAvailable() then
        return false
    end

    return self.virtual_gamepad:isInVirtualPadArea(x, y)
end

function virtual_gamepad_input:update(dt)
    if self:isAvailable() then
        self.virtual_gamepad:update(dt)
    end
end

function virtual_gamepad_input:getDebugInfo()
    if not self:isAvailable() then
        return self.name .. ": Not available"
    end

    local vx, vy, has_input = self:getMovement()
    local info = self.name .. ": Active\n"
    info = info .. "  Stick: " .. string.format("(%.2f, %.2f)", vx, vy) .. "\n"
    info = info .. "  Has Input: " .. tostring(has_input)

    return info
end

return virtual_gamepad_input

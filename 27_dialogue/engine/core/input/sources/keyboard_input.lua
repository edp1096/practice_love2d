-- systems/input/sources/keyboard_input.lua
-- Keyboard input source for movement and actions

local base_input = require "engine.core.input.sources.base_input"

local keyboard_input = {}
setmetatable(keyboard_input, { __index = base_input })
keyboard_input.__index = keyboard_input

function keyboard_input:new(input_config)
    local instance = setmetatable(base_input:new(), keyboard_input)
    instance.name = "Keyboard"
    instance.priority = 50 -- Medium priority

    -- Build action mapping from config
    instance.actions = {}
    if input_config then
        for category, actions in pairs(input_config) do
            if type(actions) == "table" and category ~= "gamepad_settings" and category ~= "button_prompts" then
                for action_name, mapping in pairs(actions) do
                    instance.actions[action_name] = mapping
                end
            end
        end
    end

    return instance
end

function keyboard_input:isAvailable()
    return self.enabled and love.keyboard ~= nil
end

function keyboard_input:getMovement()
    if not self:isAvailable() then
        return 0, 0, false
    end

    local vx, vy = 0, 0

    -- Check WASD and arrow keys
    local move_right = self.actions.move_right
    local move_left = self.actions.move_left
    local move_down = self.actions.move_down
    local move_up = self.actions.move_up

    if move_right and move_right.keyboard then
        for _, key in ipairs(move_right.keyboard) do
            if love.keyboard.isDown(key) then
                vx = vx + 1
                break
            end
        end
    end

    if move_left and move_left.keyboard then
        for _, key in ipairs(move_left.keyboard) do
            if love.keyboard.isDown(key) then
                vx = vx - 1
                break
            end
        end
    end

    if move_down and move_down.keyboard then
        for _, key in ipairs(move_down.keyboard) do
            if love.keyboard.isDown(key) then
                vy = vy + 1
                break
            end
        end
    end

    if move_up and move_up.keyboard then
        for _, key in ipairs(move_up.keyboard) do
            if love.keyboard.isDown(key) then
                vy = vy - 1
                break
            end
        end
    end

    -- Normalize diagonal movement
    if vx ~= 0 and vy ~= 0 then
        local length = math.sqrt(vx * vx + vy * vy)
        vx = vx / length
        vy = vy / length
    end

    -- Return true if any movement detected
    if vx ~= 0 or vy ~= 0 then
        return vx, vy, true
    end

    return 0, 0, false
end

function keyboard_input:getAimDirection(player_x, player_y, cam)
    -- Keyboard doesn't provide aim direction (use mouse or gamepad)
    return 0, false
end

function keyboard_input:isActionDown(action_mapping)
    if not self:isAvailable() then
        return false
    end

    if action_mapping.keyboard then
        for _, key in ipairs(action_mapping.keyboard) do
            if love.keyboard.isDown(key) then
                return true
            end
        end
    end

    return false
end

function keyboard_input:wasActionPressed(action_mapping, source, value)
    if not self:isAvailable() or source ~= "keyboard" then
        return false
    end

    if action_mapping.keyboard then
        for _, key in ipairs(action_mapping.keyboard) do
            if key == value then
                return true
            end
        end
    end

    return false
end

function keyboard_input:getDebugInfo()
    if not self:isAvailable() then
        return self.name .. ": Not available"
    end

    return self.name .. ": Active"
end

return keyboard_input

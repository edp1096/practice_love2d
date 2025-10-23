-- systems/input/sources/mouse_input.lua
-- Mouse input source for aiming

local base_input = require "systems.input.sources.base_input"

local mouse_input = {}
setmetatable(mouse_input, {__index = base_input})
mouse_input.__index = mouse_input

function mouse_input:new()
    local instance = setmetatable(base_input:new(), mouse_input)
    instance.name = "Mouse"
    instance.priority = 30 -- Lower than gamepads
    return instance
end

function mouse_input:isAvailable()
    return self.enabled and love.mouse ~= nil
end

function mouse_input:getMovement()
    -- Mouse doesn't provide movement input
    return 0, 0, false
end

function mouse_input:getAimDirection(player_x, player_y, cam)
    if not self:isAvailable() then
        return 0, false
    end
    
    -- Get mouse position in screen coordinates
    local screen_mouse_x, screen_mouse_y = love.mouse.getPosition()
    
    -- Convert player world position to screen coordinates
    local screen_player_x, screen_player_y
    if cam then
        screen_player_x, screen_player_y = cam:cameraCoords(player_x, player_y)
    else
        screen_player_x, screen_player_y = player_x, player_y
    end
    
    -- Calculate square aim area using actual screen height
    local screen = require "lib.screen"
    local aim_area_size = screen.screen_wh.h -- Actual screen pixel height
    local half_area = aim_area_size / 2
    
    -- Check if mouse is within square area centered on player (screen coordinates)
    local dx = screen_mouse_x - screen_player_x
    local dy = screen_mouse_y - screen_player_y
    
    -- Only update aim if mouse is within the square area
    if math.abs(dx) <= half_area and math.abs(dy) <= half_area then
        -- Calculate angle in world coordinates
        local world_mouse_x, world_mouse_y
        if cam then
            world_mouse_x, world_mouse_y = cam:worldCoords(screen_mouse_x, screen_mouse_y)
        else
            world_mouse_x, world_mouse_y = screen_mouse_x, screen_mouse_y
        end
        
        local mouse_angle = math.atan2(world_mouse_y - player_y, world_mouse_x - player_x)
        return mouse_angle, true
    end
    
    return 0, false
end

function mouse_input:isActionDown(action_mapping)
    if not self:isAvailable() then
        return false
    end
    
    if action_mapping.mouse then
        return love.mouse.isDown(action_mapping.mouse)
    end
    
    return false
end

function mouse_input:wasActionPressed(action_mapping, source, value)
    if not self:isAvailable() or source ~= "mouse" then
        return false
    end
    
    if action_mapping.mouse and action_mapping.mouse == value then
        return true
    end
    
    return false
end

function mouse_input:getDebugInfo()
    if not self:isAvailable() then
        return self.name .. ": Not available"
    end
    
    local mx, my = love.mouse.getPosition()
    local info = self.name .. ": Active\n"
    info = info .. "  Position: " .. string.format("(%d, %d)", mx, my)
    
    return info
end

return mouse_input

-- systems/input/input_coordinator.lua
-- Coordinates multiple input sources with priority-based selection
-- This is the clean V2 implementation that replaces complex input logic

local virtual_gamepad_input = require "systems.input.sources.virtual_gamepad_input"
local physical_gamepad_input = require "systems.input.sources.physical_gamepad_input"
local mouse_input = require "systems.input.sources.mouse_input"
local keyboard_input = require "systems.input.sources.keyboard_input"

local input_coordinator = {}

-- Initialize coordinator
function input_coordinator:init(joystick, virtual_gamepad, settings)
    self.sources = {}
    self.last_aim_angle = 0
    self.last_aim_source = "none"
    self.active_input = "keyboard_mouse" -- Track last used input device type
    self.settings = settings or {}       -- Store settings for access in vibrate method

    -- Create input sources
    self.keyboard = keyboard_input:new()
    self.mouse = mouse_input:new()

    if joystick then
        self.physical_gamepad = physical_gamepad_input:new(joystick, settings)
    end

    if virtual_gamepad then
        self.virtual_gamepad = virtual_gamepad_input:new(virtual_gamepad)
    end

    -- Register sources in priority order
    self:registerSources()
end

-- Register all input sources in priority order
function input_coordinator:registerSources()
    self.sources = {}

    -- Add sources (they auto-sort by priority)
    if self.virtual_gamepad then
        table.insert(self.sources, self.virtual_gamepad)
    end

    if self.physical_gamepad then
        table.insert(self.sources, self.physical_gamepad)
    end

    table.insert(self.sources, self.keyboard)
    table.insert(self.sources, self.mouse)

    -- Sort by priority (highest first)
    table.sort(self.sources, function(a, b)
        return a.priority > b.priority
    end)
end

-- Update all input sources
function input_coordinator:update(dt)
    for _, source in ipairs(self.sources) do
        if source:isAvailable() then
            source:update(dt)
        end
    end
end

-- Get movement from highest priority available source
function input_coordinator:getMovement()
    -- Check input sources in priority order
    for _, source in ipairs(self.sources) do
        if source:isAvailable() then
            local vx, vy, has_input = source:getMovement()
            if has_input then
                -- Update last input type based on source
                if source == self.physical_gamepad or source == self.virtual_gamepad then
                    self.active_input = "gamepad"
                elseif source == self.keyboard then
                    self.active_input = "keyboard_mouse"
                end
                return vx, vy
            end
        end
    end

    -- No input source provided movement, return zero
    return 0, 0
end

-- Get aim direction from highest priority available source
function input_coordinator:getAimDirection(player_x, player_y, cam)
    -- Special handling: check if virtual gamepad has active touches
    if self.virtual_gamepad and self.virtual_gamepad:isAvailable() then
        if self.virtual_gamepad:hasActiveTouches() then
            local angle, has_aim = self.virtual_gamepad:getAimDirection(player_x, player_y, cam)
            if has_aim then
                self.last_aim_angle = angle
                self.last_aim_source = "virtual_gamepad"
                self.active_input = "gamepad"
                return angle
            end
            return self.last_aim_angle
        end

        -- Check if mouse is in virtual gamepad area
        if self.mouse and self.mouse:isAvailable() then
            local mx, my = love.mouse.getPosition()
            if self.virtual_gamepad:isInPadArea(mx, my) then
                return self.last_aim_angle
            end
        end
    end

    -- Use aim source based on active_input
    if self.active_input == "gamepad" then
        -- Using gamepad, check physical gamepad aim
        if self.physical_gamepad and self.physical_gamepad:isAvailable() then
            local angle, has_aim = self.physical_gamepad:getAimDirection(player_x, player_y, cam)
            if has_aim then
                self.last_aim_angle = angle
                self.last_aim_source = "physicalgamepad"
                return angle
            end
        end
    else
        -- Using keyboard/mouse, check mouse aim
        if self.mouse and self.mouse:isAvailable() then
            local angle, has_aim = self.mouse:getAimDirection(player_x, player_y, cam)
            if has_aim then
                self.last_aim_angle = angle
                self.last_aim_source = "mouse"
                return angle
            end
        end
    end

    -- No aim input, return last known direction
    return self.last_aim_angle
end

-- Check if action is down from any available source
function input_coordinator:isActionDown(action_mapping)
    for _, source in ipairs(self.sources) do
        if source:isAvailable() and source:isActionDown(action_mapping) then
            -- Update active_input based on source
            if source == self.physical_gamepad or source == self.virtual_gamepad then
                self.active_input = "gamepad"
            elseif source == self.keyboard or source == self.mouse then
                self.active_input = "keyboard_mouse"
            end
            return true
        end
    end
    return false
end

-- Check if action was pressed from specific source
function input_coordinator:wasActionPressed(action_mapping, event_source, value)
    for _, source in ipairs(self.sources) do
        if source:isAvailable() and source:wasActionPressed(action_mapping, event_source, value) then
            -- Update active_input based on source
            if source == self.physical_gamepad or source == self.virtual_gamepad then
                self.active_input = "gamepad"
            elseif source == self.keyboard or source == self.mouse then
                self.active_input = "keyboard_mouse"
            end
            return true
        end
    end
    return false
end

-- Reset aim source
function input_coordinator:resetAimSource()
    self.last_aim_source = "none"
end

-- Set aim angle manually (for weapon draw initialization, etc.)
function input_coordinator:setAimAngle(angle, source)
    self.last_aim_angle = angle
    self.last_aim_source = source or "manual"
end

-- Get last aim source name
function input_coordinator:getAimSource()
    return self.last_aim_source
end

-- Vibrate physical gamepad and/or mobile device if available
function input_coordinator:vibrate(duration, left_strength, right_strength)
    -- Vibrate physical gamepad (DualSense, etc.)
    if self.physical_gamepad and self.physical_gamepad:isAvailable() then
        self.physical_gamepad:vibrate(duration, left_strength, right_strength)
    end

    -- Vibrate mobile device (Android/iOS) if enabled in settings
    if self.settings.mobile_vibration_enabled and love.system and love.system.vibrate then
        -- Calculate average strength from left and right motors
        local avg_strength = ((left_strength or 1.0) + (right_strength or left_strength or 1.0)) / 2
        -- Scale duration based on strength (stronger vibrations feel longer)
        local scaled_duration = duration * (0.5 + avg_strength * 0.5)
        love.system.vibrate(scaled_duration)
    end
end

-- Check if any gamepad (virtual or physical) is available
function input_coordinator:hasGamepad()
    if self.virtual_gamepad and self.virtual_gamepad:isAvailable() then
        return true
    end

    if self.physical_gamepad and self.physical_gamepad:isAvailable() then
        return true
    end

    return false
end

-- Update joystick reference (when controller connects/disconnects)
function input_coordinator:setJoystick(joystick, settings)
    if joystick then
        if self.physical_gamepad then
            self.physical_gamepad.joystick = joystick
            self.physical_gamepad.enabled = true
        else
            self.physical_gamepad = physical_gamepad_input:new(joystick, settings)
            self:registerSources()
        end
    else
        if self.physical_gamepad then
            self.physical_gamepad.joystick = nil
            self.physical_gamepad.enabled = false
        end
    end
end

-- Update virtual gamepad reference
function input_coordinator:setVirtualGamepad(vgp)
    if vgp then
        if self.virtual_gamepad then
            self.virtual_gamepad.virtual_gamepad = vgp
            self.virtual_gamepad.enabled = true
        else
            self.virtual_gamepad = virtual_gamepad_input:new(vgp)
            self:registerSources()
        end
    else
        if self.virtual_gamepad then
            self.virtual_gamepad.virtual_gamepad = nil
            self.virtual_gamepad.enabled = false
        end
    end
end

-- Get debug information
function input_coordinator:getDebugInfo()
    local info = "Input Coordinator:\n"
    info = info .. "  Active Sources: " .. #self.sources .. "\n"
    info = info .. "  Last Aim Source: " .. self.last_aim_source .. "\n\n"

    for i, source in ipairs(self.sources) do
        info = info .. "[" .. i .. "] " .. source:getDebugInfo() .. "\n"
    end

    return info
end

return input_coordinator

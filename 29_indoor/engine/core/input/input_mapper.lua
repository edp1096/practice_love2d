-- engine/core/input/input_mapper.lua
-- Coordinates multiple input sources with priority-based selection
-- This is the clean V2 implementation that replaces complex input logic

local virtual_pad = require "engine.core.input.sources.virtual_pad"
local gamepad = require "engine.core.input.sources.gamepad"
local mouse_input = require "engine.core.input.sources.mouse_input"
local keyboard_input = require "engine.core.input.sources.keyboard_input"
local dprint = require("engine.core.debug").dprint

local input_mapper = {}

-- Initialize coordinator
function input_mapper:init(joystick, virtual_gamepad, settings, input_config)
    self.sources = {}
    self.last_aim_angle = 0
    self.last_aim_source = "none"
    self.active_input = "keyboard_mouse" -- Track last used input device type
    self.settings = settings or {}       -- Store settings for access in vibrate method
    self.input_config = input_config     -- Store input config

    -- Game context (set by play scene)
    self.game_context = nil

    -- Scene context for input priority (set by current scene)
    self.scene_context = "gameplay" -- default: gameplay, can be "inventory", "questlog", "menu", etc.

    -- Trigger axis tracking (for Xbox controllers)
    self.trigger_state = {
        left = { pressed = false, last_value = 0 },
        right = { pressed = false, last_value = 0 }
    }
    self.trigger_threshold = 0.5 -- Threshold for trigger press

    -- Create input sources
    self.keyboard = keyboard_input:new(input_config)
    self.mouse = mouse_input:new()

    if joystick then
        self.gamepad = gamepad:new(joystick, settings, input_config)
    end

    if virtual_gamepad then
        self.virtual_pad = virtual_pad:new(virtual_gamepad)
    end

    -- Register sources in priority order
    self:registerSources()
end

-- Set game context for context-based actions
function input_mapper:setGameContext(context)
    self.game_context = context
end

-- Set scene context for input priority
function input_mapper:setSceneContext(scene_type)
    self.scene_context = scene_type or "gameplay"
end

-- Register all input sources in priority order
function input_mapper:registerSources()
    self.sources = {}

    -- Add sources (they auto-sort by priority)
    if self.virtual_pad then
        table.insert(self.sources, self.virtual_pad)
    end

    if self.gamepad then
        table.insert(self.sources, self.gamepad)
    end

    table.insert(self.sources, self.keyboard)
    table.insert(self.sources, self.mouse)

    -- Sort by priority (highest first)
    table.sort(self.sources, function(a, b)
        return a.priority > b.priority
    end)
end

-- Update all input sources
function input_mapper:update(dt)
    for _, source in ipairs(self.sources) do
        if source:isAvailable() then
            source:update(dt)
        end
    end
end

-- Get movement from highest priority available source
function input_mapper:getMovement()
    -- Check input sources in priority order
    for _, source in ipairs(self.sources) do
        if source:isAvailable() then
            local vx, vy, has_input = source:getMovement()
            if has_input then
                -- Update last input type based on source
                if source == self.gamepad or source == self.virtual_pad then
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
function input_mapper:getAimDirection(player_x, player_y, cam)
    -- Special handling: check if virtual pad has active touches
    if self.virtual_pad and self.virtual_pad:isAvailable() then
        if self.virtual_pad:hasActiveTouches() then
            local angle, has_aim = self.virtual_pad:getAimDirection(player_x, player_y, cam)
            if has_aim then
                self.last_aim_angle = angle
                self.last_aim_source = "virtual_pad"
                self.active_input = "gamepad"
                return angle
            end
            return self.last_aim_angle
        end

        -- Check if mouse is in virtual pad area
        if self.mouse and self.mouse:isAvailable() then
            local mx, my = love.mouse.getPosition()
            if self.virtual_pad:isInPadArea(mx, my) then
                return self.last_aim_angle
            end
        end
    end

    -- Use aim source based on active_input
    if self.active_input == "gamepad" then
        -- Using gamepad, check gamepad aim
        if self.gamepad and self.gamepad:isAvailable() then
            local angle, has_aim = self.gamepad:getAimDirection(player_x, player_y, cam)
            if has_aim then
                self.last_aim_angle = angle
                self.last_aim_source = "gamepad"
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
function input_mapper:isActionDown(action_mapping)
    for _, source in ipairs(self.sources) do
        if source:isAvailable() and source:isActionDown(action_mapping) then
            -- Update active_input based on source
            if source == self.gamepad or source == self.virtual_pad then
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
function input_mapper:wasActionPressed(action_mapping, event_source, value)
    for _, source in ipairs(self.sources) do
        if source:isAvailable() and source:wasActionPressed(action_mapping, event_source, value) then
            -- Update active_input based on source
            if source == self.gamepad or source == self.virtual_pad then
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
function input_mapper:resetAimSource()
    self.last_aim_source = "none"
end

-- Set aim angle manually (for weapon draw initialization, etc.)
function input_mapper:setAimAngle(angle, source)
    self.last_aim_angle = angle
    self.last_aim_source = source or "manual"
end

-- Get last aim source name
function input_mapper:getAimSource()
    return self.last_aim_source
end

-- Vibrate gamepad and/or mobile device if available
function input_mapper:vibrate(duration, left_strength, right_strength)
    -- Vibrate gamepad (DualSense, etc.)
    if self.gamepad and self.gamepad:isAvailable() then
        self.gamepad:vibrate(duration, left_strength, right_strength)
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

-- Check if any gamepad (virtual pad or gamepad) is available
function input_mapper:hasGamepad()
    if self.virtual_pad and self.virtual_pad:isAvailable() then
        return true
    end

    if self.gamepad and self.gamepad:isAvailable() then
        return true
    end

    return false
end

-- Update joystick reference (when controller connects/disconnects)
function input_mapper:setJoystick(joystick, settings)
    if joystick then
        if self.gamepad then
            self.gamepad.joystick = joystick
            self.gamepad.enabled = true
        else
            self.gamepad = gamepad:new(joystick, settings, self.input_config)
            self:registerSources()
        end
    else
        if self.gamepad then
            self.gamepad.joystick = nil
            self.gamepad.enabled = false
        end
    end
end

-- Update virtual pad reference
function input_mapper:setVirtualPad(vpad)
    if vpad then
        if self.virtual_pad then
            self.virtual_pad.virtual_gamepad = vpad
            self.virtual_pad.enabled = true
        else
            self.virtual_pad = virtual_pad:new(vpad)
            self:registerSources()
        end
    else
        if self.virtual_pad then
            self.virtual_pad.virtual_gamepad = nil
            self.virtual_pad.enabled = false
        end
    end
end

-- Define category priority based on scene context
-- Returns ordered list of categories to check (highest priority first)
local function getCategoryPriority(scene_context)
    if scene_context == "inventory" then
        return { "inventory", "system", "menu", "combat", "quest", "movement", "aim", "context" }
    elseif scene_context == "questlog" then
        return { "quest", "system", "menu", "inventory", "combat", "movement", "aim", "context" }
    elseif scene_context == "menu" then
        return { "menu", "system", "inventory", "quest", "combat", "movement", "aim", "context" }
    else
        -- gameplay (default)
        return { "combat", "movement", "aim", "context", "system", "inventory", "quest", "menu" }
    end
end

-- Handle gamepad button pressed event
-- Returns action name(s) to be handled by scene, or nil if handled internally
function input_mapper:handleGamepadPressed(joystick, button)
    dprint(string.format("scene_context=%s, button=%s", self.scene_context or "nil", button))

    -- Check context action first (A button in gameplay)
    if button == "a" and self.scene_context == "gameplay" and self.game_context then
        -- Check if we can interact with something
        local can_interact = false

        if self.game_context.world and self.game_context.player then
            local npc = self.game_context.world:getInteractableNPC(
                self.game_context.player.x,
                self.game_context.player.y
            )
            if npc then
                can_interact = true
                return "interact_npc", npc
            end

            local savepoint = self.game_context.world:getInteractableSavePoint()
            if savepoint then
                can_interact = true
                return "interact_savepoint", savepoint
            end
        end

        -- No interaction available, perform attack
        if not can_interact then
            return "attack"
        end
    end

    -- Get category priority for current scene
    local category_order = getCategoryPriority(self.scene_context)

    -- Check categories in priority order
    for _, category in ipairs(category_order) do
        local actions = self.input_config[category]
        if type(actions) == "table" then
            for action_name, mapping in pairs(actions) do
                if mapping.gamepad then
                    if type(mapping.gamepad) == "table" then
                        -- Array of buttons
                        for _, btn in ipairs(mapping.gamepad) do
                            if btn == button then
                                dprint(string.format("button=%s -> action=%s (category=%s)", button, action_name, category))
                                return action_name
                            end
                        end
                    elseif mapping.gamepad == button then
                        -- Single button
                        dprint(string.format("button=%s -> action=%s (category=%s)", button, action_name, category))
                        return action_name
                    end
                end
            end
        end
    end

    dprint(string.format("button=%s -> no action found", button))
    return nil
end

-- Handle gamepad axis movement (for trigger buttons on Xbox controllers)
-- Returns action name if trigger crossed threshold, or nil otherwise
function input_mapper:handleGamepadAxis(joystick, axis, value)
    -- Only handle trigger axes
    if axis ~= "triggerleft" and axis ~= "triggerright" then
        return nil
    end

    local trigger_side = (axis == "triggerleft") and "left" or "right"
    local trigger = self.trigger_state[trigger_side]
    local was_pressed = trigger.pressed
    local is_pressed = value > self.trigger_threshold

    -- Update state
    trigger.last_value = value
    trigger.pressed = is_pressed

    -- Detect trigger press (crossing threshold)
    if is_pressed and not was_pressed then
        -- Trigger was just pressed - check input_config for mapping
        local trigger_button = (axis == "triggerleft") and "lefttrigger" or "righttrigger"

        -- Get category priority for current scene
        local category_order = getCategoryPriority(self.scene_context)

        -- Check categories in priority order
        for _, category in ipairs(category_order) do
            local actions = self.input_config[category]
            if type(actions) == "table" then
                for action_name, mapping in pairs(actions) do
                    if mapping.gamepad then
                        if type(mapping.gamepad) == "table" then
                            -- Array of buttons
                            for _, btn in ipairs(mapping.gamepad) do
                                if btn == trigger_button then
                                    return action_name
                                end
                            end
                        elseif mapping.gamepad == trigger_button then
                            -- Single button
                            return action_name
                        end
                    end
                end
            end
        end
    end

    return nil
end

-- Get debug information
function input_mapper:getDebugInfo()
    local info = "Input Coordinator:\n"
    info = info .. "  Active Sources: " .. #self.sources .. "\n"
    info = info .. "  Last Aim Source: " .. self.last_aim_source .. "\n\n"

    for i, source in ipairs(self.sources) do
        info = info .. "[" .. i .. "] " .. source:getDebugInfo() .. "\n"
    end

    return info
end

return input_mapper

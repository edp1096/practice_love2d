-- systems/dialogue.lua
-- Simple dialogue system using Talkies with mobile SKIP/NEXT buttons

local Talkies = require "vendor.talkies"
local skip_button_widget = require "engine.ui.widgets.button.skip"
local next_button_widget = require "engine.ui.widgets.button.next"

local dialogue = {}

function dialogue:initialize()
    -- Configure Talkies
    Talkies.backgroundColor = { 0, 0, 0, 0.8 }
    Talkies.textSpeed = "fast"
    Talkies.indicatorCharacter = "█"  -- Filled box cursor

    -- Set fixed font size (will be scaled by virtual coordinates)
    -- Use 18pt as base size for 960x540 virtual resolution
    Talkies.font = love.graphics.newFont(18)

    -- Create SKIP button for mobile (rightmost)
    self.skip_button = skip_button_widget:new({
        label = "SKIP",
        width = 100,
        height = 45,
        padding_x = 20,  -- Increased to move button to the left (was 15)
        padding_y = 20,
        charge_max = 0.5,
    })
    self.skip_button.visible = false  -- Hidden by default

    -- Create NEXT button for mobile (left of SKIP)
    self.next_button = next_button_widget:new({
        label = "NEXT",
        width = 100,
        height = 45,
        padding_x = 10,
        padding_y = 20,
        button_spacing = 0,  -- Space between NEXT and SKIP
    })
    self.next_button.visible = false  -- Hidden by default
end

-- Set display reference for buttons
function dialogue:setDisplay(display)
    if self.skip_button then
        self.skip_button:init(display)
    end
    if self.next_button then
        -- Calculate NEXT button position based on SKIP button
        self.next_button:init(display)
        self.next_button:calculatePosition(self.skip_button)
    end
end

function dialogue:showSimple(npc_name, message)
    Talkies.say(npc_name, { message })
    if self.skip_button then
        self.skip_button:show()
    end
    if self.next_button then
        self.next_button:show()
    end
end

function dialogue:showMultiple(npc_name, messages)
    Talkies.say(npc_name, messages)
    if self.skip_button then
        self.skip_button:show()
    end
    if self.next_button then
        self.next_button:show()
    end
end

function dialogue:isOpen()
    return Talkies.isOpen()
end

function dialogue:update(dt)
    Talkies.update(dt)

    -- Update skip button (charge system)
    if self.skip_button and self.skip_button.visible then
        self.skip_button:update(dt)
        self.skip_button:updateHover()

        -- Check if skip was triggered (fully charged)
        if self.skip_button:isFullyCharged() then
            self:clear()
            self.skip_button:reset()
        end
    end

    -- Update next button hover state (desktop)
    if self.next_button and self.next_button.visible then
        self.next_button:updateHover()
    end

    -- Auto-hide buttons when dialogue closes
    if not Talkies.isOpen() then
        if self.skip_button and self.skip_button.visible then
            self.skip_button:hide()
        end
        if self.next_button and self.next_button.visible then
            self.next_button:hide()
        end
    end
end

function dialogue:draw()
    Talkies.draw()

    -- Draw buttons on top of dialogue
    if self.next_button then
        self.next_button:draw()
    end
    if self.skip_button then
        self.skip_button:draw()
    end
end

function dialogue:onAction()
    Talkies.onAction()
end

function dialogue:clear()
    Talkies.clearMessages()
    if self.skip_button then
        self.skip_button:hide()
    end
    if self.next_button then
        self.next_button:hide()
    end
end

-- Unified input handler for all input types
-- Returns true if dialogue consumed the input, false otherwise
function dialogue:handleInput(source, ...)
    if not self:isOpen() then
        return false
    end

    if source == "keyboard" then
        -- Keyboard: no buttons, just advance dialogue
        self:onAction()
        return true

    elseif source == "mouse" then
        local x, y = ...
        -- Mouse: check buttons first, then advance
        if not self:touchPressed(0, x, y) then
            self:onAction()
        end
        return true

    elseif source == "mouse_release" then
        local x, y = ...
        -- Mouse release: handle button actions
        self:touchReleased(0, x, y)
        return true

    elseif source == "touch" then
        local id, x, y = ...
        -- Touch: check buttons first, then advance
        if self:touchPressed(id, x, y) then
            return true  -- Button consumed
        end
        self:onAction()
        return true

    elseif source == "touch_release" then
        local id, x, y = ...
        -- Touch release: handle button actions
        return self:touchReleased(id, x, y)

    elseif source == "touch_move" then
        local id, x, y = ...
        -- Touch move: update button hover states
        self:touchMoved(id, x, y)
        return true
    end

    return false
end

-- Handle touch/mouse press on buttons
function dialogue:touchPressed(id, x, y)
    if not Talkies.isOpen() then
        return false
    end

    -- Priority 1: NEXT button (left of SKIP)
    if self.next_button and self.next_button:touchPressed(id, x, y) then
        return true  -- Consumed by next button
    end

    -- Priority 2: SKIP button
    if self.skip_button and self.skip_button:touchPressed(id, x, y) then
        return true  -- Consumed by skip button
    end

    return false
end

-- Handle touch/mouse release on buttons
function dialogue:touchReleased(id, x, y)
    if not Talkies.isOpen() then
        return false
    end

    -- Priority 1: NEXT button - advances to next message
    if self.next_button and self.next_button:touchReleased(id, x, y) then
        self:onAction()  -- Advance dialogue
        return true  -- Consumed
    end

    -- Priority 2: SKIP button - clears all dialogue (only if fully charged)
    if self.skip_button and self.skip_button:touchReleased(id, x, y) then
        -- touchReleased returns true only if fully charged
        self:clear()  -- Clear all dialogue
        return true  -- Consumed
    end

    return false
end

-- Handle touch/mouse move
function dialogue:touchMoved(id, x, y)
    if Talkies.isOpen() then
        if self.skip_button then
            self.skip_button:touchMoved(id, x, y)
        end
        if self.next_button then
            self.next_button:touchMoved(id, x, y)
        end
    end
end

return dialogue

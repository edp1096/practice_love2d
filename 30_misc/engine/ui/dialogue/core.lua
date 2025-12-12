-- engine/ui/dialogue/core.lua
-- Core dialogue system: initialization, simple dialogue, state management, input handling

local utf8 = require "utf8"
local skip_button_widget = require "engine.ui.widgets.button.skip"
local next_button_widget = require "engine.ui.widgets.button.next"
local locale = require "engine.core.locale"

local core = {}

-- Module-level font storage
core.font = nil

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function core:initialize(dialogue, display_module)
    -- Set dialogue font (will be scaled by virtual coordinates)
    core.font = locale:getFont("option") or love.graphics.newFont(18)

    -- Create SKIP button for mobile (rightmost)
    dialogue.skip_button = skip_button_widget:new({
        label = "SKIP",
        width = 100,
        height = 45,
        padding_x = 20,
        padding_y = 20,
        charge_max = 0.5,
    })
    dialogue.skip_button.visible = false

    -- Create NEXT button for mobile (left of SKIP)
    dialogue.next_button = next_button_widget:new({
        label = "NEXT",
        width = 100,
        height = 45,
        padding_x = 10,
        padding_y = 20,
        button_spacing = 0,
    })
    dialogue.next_button.visible = false

    -- Choice system state
    dialogue.tree_mode = false
    dialogue.current_tree = nil
    dialogue.current_node_id = nil
    dialogue.current_choices = nil
    dialogue.pending_choices = nil
    dialogue.selected_choice_index = 1
    dialogue.choice_font = locale:getFont("option") or love.graphics.newFont(16)

    -- Force closed flag
    dialogue.forced_closed = false

    -- Display reference
    dialogue.display = nil

    -- Dialogue registry (injected from game)
    if not dialogue.dialogue_registry then
        dialogue.dialogue_registry = {}
    end

    -- Paged dialogue state
    dialogue.current_pages = nil
    dialogue.current_page_index = 0
    dialogue.total_pages = 0
    dialogue.showing_paged_text = false
    dialogue.showing_single_text = false

    -- Selected choices tracking (for grey-out effect)
    dialogue.selected_choices = {}

    -- Global storage for ALL dialogue choices (for persistence)
    if not dialogue.all_dialogue_choices then
        dialogue.all_dialogue_choices = {}
    end

    -- Current dialogue ID
    dialogue.current_dialogue_id = nil

    -- Track which choice was pressed
    dialogue.pressed_choice_index = nil

    -- Typewriter effect state
    dialogue.typewriter_position = 0
    dialogue.typewriter_complete = true
    dialogue.typewriter_speed = 0.03
    dialogue.typewriter_sound_interval = 3
    dialogue.typewriter_last_sound_pos = 0
    dialogue.typing_sound = "dialogue_typing"

    -- Quest system reference (injected from game)
    if not dialogue.quest_system then
        dialogue.quest_system = nil
    end

    -- Dialogue flags system (for conditional logic)
    if not dialogue.dialogue_flags then
        dialogue.dialogue_flags = {}
    end

    -- Initialize display if provided
    if display_module then
        self:setDisplay(dialogue, display_module)
    end
end

-- Set display reference for buttons
function core:setDisplay(dialogue, display)
    dialogue.display = display
    if dialogue.skip_button then
        dialogue.skip_button:init(display)
    end
    if dialogue.next_button then
        dialogue.next_button:init(display)
        dialogue.next_button:calculatePosition(dialogue.skip_button)
    end
end

-- ============================================================================
-- SIMPLE DIALOGUE METHODS (non-interactive)
-- ============================================================================

-- Show simple dialogue (single message)
function core:showSimple(dialogue, npc_name, message, typing_sound)
    local typewriter = require "engine.ui.dialogue.typewriter"

    dialogue.forced_closed = false
    dialogue.tree_mode = false
    dialogue.current_choices = nil
    dialogue.typing_sound = typing_sound or "dialogue_typing"

    -- Use paged mode with single page
    dialogue.current_pages = { message }
    dialogue.current_page_index = 0
    dialogue.total_pages = 1
    dialogue.showing_paged_text = true
    dialogue.showing_single_text = false
    dialogue.current_speaker = npc_name or ""
    dialogue.current_text = message

    typewriter:reset(dialogue)

    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- Show multiple messages in sequence
function core:showMultiple(dialogue, npc_name, messages, typing_sound)
    local typewriter = require "engine.ui.dialogue.typewriter"

    dialogue.forced_closed = false
    dialogue.tree_mode = false
    dialogue.current_choices = nil
    dialogue.typing_sound = typing_sound or "dialogue_typing"

    -- Use paged mode
    dialogue.current_pages = messages
    dialogue.current_page_index = 0
    dialogue.total_pages = #messages
    dialogue.showing_paged_text = true
    dialogue.showing_single_text = false
    dialogue.current_speaker = npc_name or ""
    dialogue.current_text = messages[1] or ""

    typewriter:reset(dialogue)

    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- ============================================================================
-- CORE STATE METHODS
-- ============================================================================

function core:isOpen(dialogue)
    if dialogue.forced_closed then
        return false
    end
    return dialogue.tree_mode or dialogue.showing_paged_text or dialogue.showing_single_text
end

function core:update(dialogue, dt)
    local typewriter = require "engine.ui.dialogue.typewriter"
    local tree = require "engine.ui.dialogue.tree"

    -- Update button visibility each frame
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)

    -- Update typewriter effect
    typewriter:update(dialogue, dt)

    -- Update skip button (charge system)
    if dialogue.skip_button and dialogue.skip_button.visible then
        dialogue.skip_button:update(dt)
        dialogue.skip_button:updateHover()

        if dialogue.skip_button:isFullyCharged() then
            self:clear(dialogue)
            dialogue.skip_button:reset()
        end
    end

    -- Update next button hover state (desktop)
    if dialogue.next_button and dialogue.next_button.visible then
        dialogue.next_button:updateHover()
    end

    -- Check gamepad left stick for choice navigation
    if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
        local joysticks = love.joystick.getJoysticks()
        if #joysticks > 0 then
            local joystick = joysticks[1]
            local ly = joystick:getGamepadAxis("lefty")
            local threshold = 0.5

            if not dialogue.stick_cooldown then
                dialogue.stick_cooldown = 0
            end

            if dialogue.stick_cooldown > 0 then
                dialogue.stick_cooldown = dialogue.stick_cooldown - dt
            else
                if ly < -threshold then
                    tree:moveChoiceSelection(dialogue, "up")
                    dialogue.stick_cooldown = 0.25
                elseif ly > threshold then
                    tree:moveChoiceSelection(dialogue, "down")
                    dialogue.stick_cooldown = 0.25
                end
            end
        end
    end
end

function core:onAction(dialogue)
    local typewriter = require "engine.ui.dialogue.typewriter"
    local tree = require "engine.ui.dialogue.tree"

    if dialogue.tree_mode then
        -- Tree mode: handle choice selection or advance
        if dialogue.current_choices and #dialogue.current_choices > 0 then
            if not dialogue.typewriter_complete then
                typewriter:skip(dialogue)
                return
            end
            tree:selectChoice(dialogue, dialogue.selected_choice_index)
        else
            tree:advanceTree(dialogue)
        end
    else
        -- Simple dialogue mode (showSimple/showMultiple)
        if dialogue.showing_paged_text and dialogue.current_pages then
            if not dialogue.typewriter_complete then
                typewriter:skip(dialogue)
                return
            end

            if dialogue.current_page_index < dialogue.total_pages - 1 then
                dialogue.current_page_index = dialogue.current_page_index + 1
                dialogue.current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
                typewriter:reset(dialogue)
                return
            else
                self:clear(dialogue)
            end
        end

        local render = require "engine.ui.dialogue.render"
        render:updateButtonVisibility(dialogue)
    end
end

function core:clear(dialogue)
    -- Set forced_closed flag FIRST
    dialogue.forced_closed = true

    -- Clear tree state
    dialogue.tree_mode = false
    dialogue.current_tree = nil
    dialogue.current_node_id = nil
    dialogue.current_choices = nil
    dialogue.pending_choices = nil
    dialogue.selected_choice_index = 1

    -- Clear paged dialogue state
    dialogue.current_pages = nil
    dialogue.current_page_index = 0
    dialogue.total_pages = 0
    dialogue.showing_paged_text = false
    dialogue.showing_single_text = false

    -- Update button visibility
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================

-- Unified input handler for all input types
-- Returns true if dialogue consumed the input, false otherwise
function core:handleInput(dialogue, source, ...)
    if not self:isOpen(dialogue) then
        return false
    end

    local helpers = require "engine.ui.dialogue.helpers"
    local tree = require "engine.ui.dialogue.tree"

    if source == "keyboard" then
        local key = ...
        local input_sys = require "engine.core.input"
        if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
            if input_sys:wasPressed("move_up", "keyboard", key) then
                tree:moveChoiceSelection(dialogue, "up")
                return true
            elseif input_sys:wasPressed("move_down", "keyboard", key) then
                tree:moveChoiceSelection(dialogue, "down")
                return true
            end
        end
        self:onAction(dialogue)
        return true

    elseif source == "mouse" then
        local x, y = ...
        if not helpers:touchPressed(dialogue, 0, x, y) then
            if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
                -- Choices exist: only allow click to skip typewriter (not select)
                if not dialogue.typewriter_complete then
                    self:onAction(dialogue)
                end
                -- After typewriter complete, clicks outside choice buttons are ignored
            else
                self:onAction(dialogue)
            end
        end
        return true

    elseif source == "mouse_release" then
        local x, y = ...
        return helpers:touchReleased(dialogue, 0, x, y)

    elseif source == "touch" then
        local id, x, y = ...
        if helpers:touchPressed(dialogue, id, x, y) then
            return true
        end
        if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
            -- Choices exist: only allow touch to skip typewriter (not select)
            if not dialogue.typewriter_complete then
                self:onAction(dialogue)
            end
            -- After typewriter complete, touches outside choice buttons are ignored
        else
            self:onAction(dialogue)
        end
        return true

    elseif source == "touch_release" then
        local id, x, y = ...
        return helpers:touchReleased(dialogue, id, x, y)

    elseif source == "touch_move" then
        local id, x, y = ...
        helpers:touchMoved(dialogue, id, x, y)
        return false

    elseif source == "gamepad" then
        local button = ...
        if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
            local input_sys = require "engine.core.input"

            if input_sys:wasPressed("move_up", "gamepad", button) then
                tree:moveChoiceSelection(dialogue, "up")
                return true
            elseif input_sys:wasPressed("move_down", "gamepad", button) then
                tree:moveChoiceSelection(dialogue, "down")
                return true
            end
        end
        self:onAction(dialogue)
        return true
    end

    return false
end

return core

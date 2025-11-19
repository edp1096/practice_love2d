-- engine/ui/dialogue/init.lua
-- Core dialogue system logic: initialization, tree system, node management

local Talkies = require "vendor.talkies"
local skip_button_widget = require "engine.ui.widgets.button.skip"
local next_button_widget = require "engine.ui.widgets.button.next"
local colors = require "engine.utils.colors"

local core = {}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function core:initialize(dialogue, display_module)
    -- Configure Talkies
    Talkies.backgroundColor = colors.for_dialogue_bg
    Talkies.messageBorderColor = colors.for_dialogue_text  -- Border color
    Talkies.thickness = 2  -- Border thickness (match our custom dialogues)
    Talkies.rounding = 4  -- Rounded corners (match our custom dialogues)
    Talkies.textSpeed = "fast"
    Talkies.indicatorCharacter = "█"  -- Filled box cursor

    -- Set fixed font size (will be scaled by virtual coordinates)
    -- Use 18pt as base size for 960x540 virtual resolution
    Talkies.font = love.graphics.newFont(18)

    -- Create SKIP button for mobile (rightmost)
    dialogue.skip_button = skip_button_widget:new({
        label = "SKIP",
        width = 100,
        height = 45,
        padding_x = 20,  -- Increased to move button to the left (was 15)
        padding_y = 20,
        charge_max = 0.5,
    })
    dialogue.skip_button.visible = false  -- Hidden by default

    -- Create NEXT button for mobile (left of SKIP)
    dialogue.next_button = next_button_widget:new({
        label = "NEXT",
        width = 100,
        height = 45,
        padding_x = 10,
        padding_y = 20,
        button_spacing = 0,  -- Space between NEXT and SKIP
    })
    dialogue.next_button.visible = false  -- Hidden by default

    -- Choice system state
    dialogue.tree_mode = false           -- true when showing dialogue tree
    dialogue.current_tree = nil          -- Current dialogue tree data
    dialogue.current_node_id = nil       -- Current node ID
    dialogue.current_choices = nil       -- Current choice buttons (visible now)
    dialogue.pending_choices = nil       -- Pending choices (show after text)
    dialogue.selected_choice_index = 1  -- Currently selected choice (for keyboard/gamepad)
    dialogue.choice_font = love.graphics.newFont(16)

    -- Force closed flag (prevents reopening until new dialogue starts)
    dialogue.forced_closed = false

    -- Display reference
    dialogue.display = nil

    -- Dialogue registry (injected from game) - preserve if already set
    if not dialogue.dialogue_registry then
        dialogue.dialogue_registry = {}
    end

    -- Paged dialogue state
    dialogue.current_pages = nil
    dialogue.current_page_index = 0
    dialogue.total_pages = 0
    dialogue.showing_paged_text = false

    -- Selected choices tracking (for grey-out effect) - PER DIALOGUE
    -- Format: { "{node_id}|{choice_text}" = true }
    dialogue.selected_choices = {}

    -- Global storage for ALL dialogue choices (for persistence)
    -- Format: { dialogue_id = { "{node_id}|{choice_text}" = true, ... }, ... }
    -- Preserve existing data if already set (for save/load)
    if not dialogue.all_dialogue_choices then
        dialogue.all_dialogue_choices = {}
    end

    -- Current dialogue ID (for save/load)
    dialogue.current_dialogue_id = nil

    -- Track which choice was pressed (to prevent click-through)
    dialogue.pressed_choice_index = nil

    -- Quest system reference (injected from game) - preserve if already set
    if not dialogue.quest_system then
        dialogue.quest_system = nil
    end

    -- Dialogue flags system (for conditional logic)
    -- Format: { dialogue_id = { flag_name = value, ... }, ... }
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
        -- Calculate NEXT button position based on SKIP button
        dialogue.next_button:init(display)
        dialogue.next_button:calculatePosition(dialogue.skip_button)
    end
end

-- ============================================================================
-- DIALOGUE TREE SYSTEM
-- ============================================================================

-- Start a dialogue tree by ID (loads from registry)
function core.showTreeById(dialogue, dialogue_id, npc_id, npc_obj)
    print(string.format("[showTreeById] dialogue_id=%s, npc_id=%s, npc_obj type=%s",
        tostring(dialogue_id),
        tostring(npc_id),
        type(npc_obj)))

    local dialogue_tree = dialogue.dialogue_registry[dialogue_id]
    if not dialogue_tree then
        return
    end
    -- Store dialogue ID for persistence
    dialogue.current_dialogue_id = dialogue_id
    -- Store NPC object for transformations
    dialogue.current_npc = npc_obj

    print(string.format("[showTreeById] dialogue.current_npc set: %s", tostring(dialogue.current_npc ~= nil)))

    -- Override NPC ID if provided (for dynamic NPC association)
    if npc_id then
        -- Clone the tree to avoid modifying the original
        local tree_copy = {}
        for k, v in pairs(dialogue_tree) do
            tree_copy[k] = v
        end
        tree_copy.npc_id = npc_id
        core.showTree(dialogue, tree_copy)
    else
        core.showTree(dialogue, dialogue_tree)
    end
end

-- Start a dialogue tree (choice-based conversation)
function core.showTree(dialogue, dialogue_tree)
    local self = core  -- Restore self reference for other function calls

    if not dialogue_tree or not dialogue_tree.nodes then
        return
    end

    print(string.format("[showTree] BEFORE: current_npc=%s", tostring(dialogue.current_npc ~= nil)))

    -- Reset forced_closed flag (allowing dialogue to open)
    dialogue.forced_closed = false

    -- Store NPC ID for quest lookups (if provided)
    dialogue.current_npc_id = dialogue_tree.npc_id
    print(string.format("[SHOW_TREE] dialogue_id=%s, tree.npc_id=%s, current_npc_id=%s, current_npc=%s",
        tostring(dialogue.current_dialogue_id),
        tostring(dialogue_tree.npc_id),
        tostring(dialogue.current_npc_id),
        tostring(dialogue.current_npc ~= nil)))

    -- Load selected choices for this dialogue (instead of resetting)
    if dialogue.current_dialogue_id then
        -- Ensure global storage exists for this dialogue
        if not dialogue.all_dialogue_choices[dialogue.current_dialogue_id] then
            dialogue.all_dialogue_choices[dialogue.current_dialogue_id] = {}
        end
        -- Share the same table reference (not a copy!)
        dialogue.selected_choices = dialogue.all_dialogue_choices[dialogue.current_dialogue_id]
    else
        -- No dialogue ID - use temporary table
        dialogue.selected_choices = {}
    end

    -- Enter tree mode
    dialogue.tree_mode = true
    dialogue.current_tree = dialogue_tree
    dialogue.current_node_id = dialogue_tree.start_node or "start"
    dialogue.selected_choice_index = 1

    -- Show first node
    self:showNode(dialogue, dialogue.current_node_id)

    -- Update button visibility based on new state
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- Display a specific node
function core:showNode(dialogue, node_id)
    local node = dialogue.current_tree.nodes[node_id]
    if not node then
        self:clear(dialogue)
        return
    end

    -- Update current node
    dialogue.current_node_id = node_id

    -- Check for on_enter callback (dynamic routing)
    if node.on_enter then
        local context = {
            dialogue_id = dialogue.current_dialogue_id,
            node_id = node_id,
            quest_system = dialogue.quest_system,
            dialogue_system = dialogue,
        }
        local redirect_node = node.on_enter(context)
        if redirect_node and redirect_node ~= node_id then
            -- Redirect to different node
            self:showNode(dialogue, redirect_node)
            return
        end
    end

    -- Check for quest_offer node type (dynamic quest dialogue generation)
    if node.type == "quest_offer" then
        -- Find available quest for this NPC
        -- Use node.npc_id if specified, otherwise use current NPC from dialogue
        local npc_id = node.npc_id or dialogue.current_npc_id
        local quest_system = dialogue.quest_system

        if quest_system and quest_system.quest_registry and npc_id then
            -- Find first available quest for this NPC
            local available_quest = nil
            for quest_id, quest_data in pairs(quest_system.quest_registry) do
                if quest_data.giver_npc == npc_id and quest_data.dialogue then
                    -- Check quest state first
                    local quest_state = quest_system.quest_states[quest_id]
                    local state_str = quest_state and quest_state.state or "NO_STATE"

                    -- Use canAccept() to check prerequisites
                    local can_accept = quest_system:canAccept(quest_id)

                    if can_accept then
                        available_quest = { id = quest_id, data = quest_data }
                        break
                    end
                end
            end

            if available_quest then
                -- Generate quest offer node dynamically
                local quest_id = available_quest.id
                local quest_data = available_quest.data
                local dlg = quest_data.dialogue

                -- Create virtual node with quest offer text
                local virtual_node = {
                    text = dlg.offer_text,
                    speaker = node.speaker or "???",
                    choices = {
                        {
                            text = "Accept Quest",
                            next = "quest_accepted_" .. quest_id,
                            action = {
                                type = "accept_quest",
                                quest_id = quest_id
                            }
                        },
                        {
                            text = "Decline",
                            next = dlg.decline_response or "end"
                        }
                    }
                }

                -- Create acceptance response virtual node (persistent)
                dialogue.current_tree.nodes["quest_accepted_" .. quest_id] = {
                    text = dlg.accept_text,
                    speaker = node.speaker or "???",
                    choices = {
                        { text = "Continue", next = dlg.decline_response or "end" }
                    }
                }

                -- IMPORTANT: Don't store virtual_node in tree!
                -- quest_offer nodes are dynamic - they regenerate on each visit
                -- Just replace current node for immediate display
                node = virtual_node
            else
                -- No available quests - redirect to fallback or end
                local fallback = node.no_quest_fallback or "end"
                if fallback == "end" then
                    self:clear(dialogue)
                    return
                else
                    self:showNode(dialogue, fallback)
                    return
                end
            end
        else
            -- No quest system or NPC - redirect to fallback or end
            local fallback = node.no_quest_fallback or "end"
            if fallback == "end" then
                self:clear(dialogue)
                return
            else
                self:showNode(dialogue, fallback)
                return
            end
        end
    end

    -- Check if node has pages (multi-page dialogue)
    if node.pages and #node.pages > 0 then
        -- Paged mode: store pages and start at page 0
        dialogue.current_pages = node.pages
        dialogue.current_page_index = 0
        dialogue.total_pages = #node.pages
        dialogue.showing_paged_text = true

        -- Don't show Talkies, we'll render pages ourselves
        Talkies.clearMessages()
    elseif node.choices and #node.choices > 0 then
        -- Node has choices: skip Talkies, show custom dialogue box directly
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0
        dialogue.showing_paged_text = false
        Talkies.clearMessages()
    else
        -- Single text mode: use Talkies
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0
        dialogue.showing_paged_text = false

        local speaker = node.speaker or "???"
        Talkies.say(speaker, { node.text })
    end

    -- Setup choices (if any) - with conditional filtering
    if node.choices and #node.choices > 0 then
        -- Filter choices based on conditions
        local helpers = require "engine.ui.dialogue.helpers"
        local filtered_choices = helpers:filterChoicesByCondition(
            dialogue,
            node.choices,
            dialogue.current_dialogue_id,
            dialogue.current_node_id
        )

        if #filtered_choices > 0 then
            if dialogue.showing_paged_text then
                -- Paged mode: choices are pending (show after last page)
                dialogue.pending_choices = filtered_choices
                dialogue.current_choices = nil
            else
                -- Non-paged mode: show choices immediately
                dialogue.current_choices = filtered_choices
                dialogue.pending_choices = nil
            end
            dialogue.selected_choice_index = 1
        else
            -- No visible choices after filtering
            dialogue.current_choices = nil
            dialogue.pending_choices = nil
            dialogue.selected_choice_index = 1
        end
    else
        -- No choices - this node ends dialogue or auto-advances
        dialogue.current_choices = nil
        dialogue.pending_choices = nil
        dialogue.selected_choice_index = 1
    end

    -- Store current node for rendering (especially for dynamic virtual nodes)
    dialogue.current_node = node

    -- Execute node action (if any) - for node-level actions like NPC transformations
    if node.action then
        print(string.format("[showNode] Executing node action: type=%s", tostring(node.action.type)))
        local helpers = require "engine.ui.dialogue.helpers"
        helpers:executeAction(dialogue, node.action)
    end

    -- Update button visibility (hide if choices shown)
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- Advance dialogue tree (called when player presses action)
function core:advanceTree(dialogue)
    if not dialogue.tree_mode then
        return
    end

    local node = dialogue.current_tree.nodes[dialogue.current_node_id]
    if not node then
        self:clear(dialogue)
        return
    end

    -- PAGED MODE: Handle page navigation
    if dialogue.showing_paged_text and dialogue.current_pages then
        -- Advance to next page
        if dialogue.current_page_index < dialogue.total_pages - 1 then
            dialogue.current_page_index = dialogue.current_page_index + 1
            return
        else
            -- Last page reached - show choices or continue
            if dialogue.pending_choices and #dialogue.pending_choices > 0 then
                -- Activate pending choices
                dialogue.current_choices = dialogue.pending_choices
                dialogue.pending_choices = nil
                dialogue.selected_choice_index = 1
                return
            elseif dialogue.current_choices and #dialogue.current_choices > 0 then
                -- Choices already shown (stay in paged mode)
                return
            else
                -- No choices - advance to next node or end
                if node.next then
                    self:showNode(dialogue, node.next)
                else
                    self:clear(dialogue)
                end
                return
            end
        end
    end

    -- TALKIES MODE: Handle Talkies text
    if Talkies.isOpen() and not Talkies.paused then
        Talkies.onAction()
        -- CRITICAL: Update button visibility after Talkies advances
        local render = require "engine.ui.dialogue.render"
        render:updateButtonVisibility(dialogue)

        -- If Talkies is still open (more messages), wait for next click
        if Talkies.isOpen() then
            return
        end
        -- Otherwise, continue to check for next node/choices (fall through)
    end

    -- Check for pending choices (text was shown, now show choices)
    if dialogue.pending_choices then
        dialogue.current_choices = dialogue.pending_choices
        dialogue.pending_choices = nil
        local render = require "engine.ui.dialogue.render"
        render:updateButtonVisibility(dialogue)  -- Hide buttons when choices shown
        return
    end

    -- If node has choices, wait for player to select
    if dialogue.current_choices and #dialogue.current_choices > 0 then
        return
    end

    -- No choices - check for auto-advance
    if node.next then
        self:showNode(dialogue, node.next)
    else
        self:clear(dialogue)
    end
end

-- Select a choice (keyboard/gamepad navigation)
function core:selectChoice(dialogue, choice_index)
    if not dialogue.tree_mode or not dialogue.current_choices then
        return
    end

    local choice = dialogue.current_choices[choice_index]
    if not choice then
        return
    end

    -- Prevent selecting disabled choices
    if choice._is_disabled then
        return
    end

    -- Mark this choice as selected (for grey-out effect)
    -- Exception: Don't mark "Other quest?" as selected (should remain available)
    if choice.text ~= "Other quest?" then
        local choice_key = dialogue.current_node_id .. "|" .. choice.text
        dialogue.selected_choices[choice_key] = true

        -- Note: dialogue.selected_choices is already a reference to
        -- dialogue.all_dialogue_choices[dialogue.current_dialogue_id]
        -- so no need to update global storage separately
    end

    -- Execute choice action (if any)
    if choice.action then
        local helpers = require "engine.ui.dialogue.helpers"
        helpers:executeAction(dialogue, choice.action)
    end

    -- Execute on_select callback (for custom game logic like NPC→Enemy transformation)
    if choice.on_select and dialogue.game_context then
        choice.on_select(dialogue.game_context)
    end

    -- Navigate to next node
    if choice.next then
        -- Clear current state completely before navigating
        Talkies.clearMessages()
        dialogue.showing_paged_text = false
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0

        self:showNode(dialogue, choice.next)
    else
        -- No next - end dialogue
        self:clear(dialogue)
    end
end

-- Navigate choice selection (keyboard/gamepad)
function core:moveChoiceSelection(dialogue, direction)
    if not dialogue.tree_mode or not dialogue.current_choices then
        return
    end

    local count = #dialogue.current_choices
    if direction == "up" then
        dialogue.selected_choice_index = dialogue.selected_choice_index - 1
        if dialogue.selected_choice_index < 1 then
            dialogue.selected_choice_index = count
        end
    elseif direction == "down" then
        dialogue.selected_choice_index = dialogue.selected_choice_index + 1
        if dialogue.selected_choice_index > count then
            dialogue.selected_choice_index = 1
        end
    end
end

-- ============================================================================
-- SIMPLE DIALOGUE METHODS (non-interactive)
-- ============================================================================

function core:showSimple(dialogue, npc_name, message)
    dialogue.forced_closed = false  -- Reset forced_closed (allowing dialogue to open)
    dialogue.tree_mode = false  -- Disable tree mode
    dialogue.current_choices = nil  -- No choices
    Talkies.say(npc_name, { message })

    -- Update button visibility (event-based, not polling)
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

function core:showMultiple(dialogue, npc_name, messages)
    dialogue.forced_closed = false  -- Reset forced_closed (allowing dialogue to open)
    dialogue.tree_mode = false  -- Disable tree mode
    dialogue.current_choices = nil  -- No choices
    Talkies.say(npc_name, messages)

    -- Update button visibility (event-based, not polling)
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- ============================================================================
-- CORE STATE METHODS
-- ============================================================================

function core:isOpen(dialogue)
    -- If forced closed, dialogue is definitively closed
    if dialogue.forced_closed then
        return false
    end
    -- Otherwise, check Talkies or tree mode
    return Talkies.isOpen() or dialogue.tree_mode
end

function core:update(dialogue, dt)
    Talkies.update(dt)

    -- CRITICAL: Poll dialogue state every frame to detect auto-close
    -- (Talkies can close itself when all messages are consumed)
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)

    -- Update skip button (charge system)
    if dialogue.skip_button and dialogue.skip_button.visible then
        dialogue.skip_button:update(dt)
        dialogue.skip_button:updateHover()

        -- Check if skip was triggered (fully charged)
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

            -- Cooldown system to prevent rapid repeated movement
            if not dialogue.stick_cooldown then
                dialogue.stick_cooldown = 0
            end

            if dialogue.stick_cooldown > 0 then
                dialogue.stick_cooldown = dialogue.stick_cooldown - dt
            else
                if ly < -threshold then
                    -- Stick up -> move selection up
                    self:moveChoiceSelection(dialogue, "up")
                    dialogue.stick_cooldown = 0.25  -- 0.25 second cooldown
                elseif ly > threshold then
                    -- Stick down -> move selection down
                    self:moveChoiceSelection(dialogue, "down")
                    dialogue.stick_cooldown = 0.25
                end
            end
        end
    end
end

function core:onAction(dialogue)
    if dialogue.tree_mode then
        -- Tree mode: handle choice selection or advance
        if dialogue.current_choices and #dialogue.current_choices > 0 then
            self:selectChoice(dialogue, dialogue.selected_choice_index)
        else
            -- No choices - advance tree
            self:advanceTree(dialogue)
        end
    else
        -- Simple dialogue mode: advance Talkies and update button state
        Talkies.onAction()

        -- CRITICAL: Update button visibility after advancing
        -- If Talkies closed (no more messages), hide buttons
        local render = require "engine.ui.dialogue.render"
        render:updateButtonVisibility(dialogue)
    end
end

function core:clear(dialogue)
    -- Set forced_closed flag FIRST (this makes isOpen() return false immediately)
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

    -- Clear Talkies message queue
    Talkies.clearMessages()

    -- Pop current dialog if exists (safe pop - max 10 times to avoid infinite loop)
    local max_pops = 10
    local count = 0
    while Talkies.isOpen() and count < max_pops do
        if Talkies.dialogs and Talkies.dialogs.pop then
            Talkies.dialogs:pop()
            count = count + 1
        else
            break
        end
    end

    -- Update button visibility (will hide since forced_closed is true)
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

    if source == "keyboard" then
        -- Keyboard: check for choice navigation first
        local key = ...
        local input_sys = require "engine.core.input"
        if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
            if input_sys:wasPressed("move_up", "keyboard", key) then
                self:moveChoiceSelection(dialogue, "up")
                return true
            elseif input_sys:wasPressed("move_down", "keyboard", key) then
                self:moveChoiceSelection(dialogue, "down")
                return true
            end
        end
        -- Otherwise, advance dialogue/select choice
        self:onAction(dialogue)
        return true

    elseif source == "mouse" then
        local x, y = ...
        -- Mouse: check buttons first, then advance
        if not helpers:touchPressed(dialogue, 0, x, y) then
            -- Only advance if no choices are displayed (prevent accidental selection)
            if not (dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0) then
                self:onAction(dialogue)
            end
        end
        return true

    elseif source == "mouse_release" then
        local x, y = ...
        -- Mouse release: handle button actions
        return helpers:touchReleased(dialogue, 0, x, y)

    elseif source == "touch" then
        local id, x, y = ...
        -- Touch: check buttons first, then advance
        if helpers:touchPressed(dialogue, id, x, y) then
            return true  -- Button consumed
        end
        -- Only advance if no choices are displayed (prevent accidental selection)
        if not (dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0) then
            self:onAction(dialogue)
        end
        return true

    elseif source == "touch_release" then
        local id, x, y = ...
        -- Touch release: handle button actions
        return helpers:touchReleased(dialogue, id, x, y)

    elseif source == "touch_move" then
        local id, x, y = ...
        -- Touch move: update button hover states (doesn't consume input)
        helpers:touchMoved(dialogue, id, x, y)
        return false

    elseif source == "gamepad" then
        -- Gamepad: check for choice navigation first
        local button = ...
        if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
            local input_sys = require "engine.core.input"

            -- D-pad or left stick navigation
            if input_sys:wasPressed("move_up", "gamepad", button) then
                self:moveChoiceSelection(dialogue, "up")
                return true
            elseif input_sys:wasPressed("move_down", "gamepad", button) then
                self:moveChoiceSelection(dialogue, "down")
                return true
            end
        end
        -- Otherwise, advance dialogue/select choice with A/Cross button
        self:onAction(dialogue)
        return true
    end

    return false
end

return core

-- engine/ui/dialogue/core.lua
-- Core dialogue system logic: initialization, tree system, node management

local utf8 = require "utf8"
local skip_button_widget = require "engine.ui.widgets.button.skip"
local next_button_widget = require "engine.ui.widgets.button.next"
local colors = require "engine.utils.colors"
local locale = require "engine.core.locale"

local core = {}

-- Module-level font storage (replaces Talkies.font)
core.font = nil

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Helper: Resolve text from localization key or direct value
local function resolveTextKey(key, fallback, default)
    default = default or ""
    if not key then return fallback or default end

    local translated = locale:t(key)
    -- i18n returns the key itself if translation not found
    if translated ~= key then
        return translated
    end
    return fallback or default
end

-- Helper: Handle fallback for quest offer nodes
local function handleQuestFallback(self, dialogue, node)
    local fallback = node.no_quest_fallback or "end"
    if fallback == "end" then
        return "clear"
    else
        self:showNode(dialogue, fallback)
        return "redirect"
    end
end

-- Helper: Translate choice texts using locale
local function translateChoices(choices)
    local translated = {}
    for _, choice in ipairs(choices) do
        local translated_choice = {}
        for k, v in pairs(choice) do
            translated_choice[k] = v
        end
        translated_choice.text = resolveTextKey(choice.text_key, choice.text)
        table.insert(translated, translated_choice)
    end
    return translated
end

-- Helper: Find first available quest for NPC
local function findAvailableQuest(quest_system, npc_id)
    if not (quest_system and quest_system.quest_registry and npc_id) then
        return nil
    end

    for quest_id, quest_data in pairs(quest_system.quest_registry) do
        if quest_data.giver_npc == npc_id and quest_data.dialogue then
            if quest_system:canAccept(quest_id) then
                return { id = quest_id, data = quest_data }
            end
        end
    end
    return nil
end

-- Handle quest_offer node type (dynamic quest dialogue generation)
-- Returns: virtual_node table, "clear", "redirect", or nil
function core:handleQuestOffer(dialogue, node)
    local npc_id = node.npc_id or dialogue.current_npc_id
    local quest_system = dialogue.quest_system

    local available_quest = findAvailableQuest(quest_system, npc_id)

    if not available_quest then
        return handleQuestFallback(self, dialogue, node)
    end

    -- Generate quest offer node dynamically
    local quest_id = available_quest.id
    local quest_data = available_quest.data
    local dlg = quest_data.dialogue

    local offer_text = resolveTextKey(dlg.offer_text_key, dlg.offer_text)
    local accept_text = resolveTextKey(dlg.accept_text_key, dlg.accept_text)
    local speaker = resolveTextKey(node.speaker_key, node.speaker, "???")

    -- Create virtual node with quest offer text
    local virtual_node = {
        text = offer_text,
        speaker = speaker,
        choices = {
            {
                text = locale:t("quest.accept"),
                next = "quest_accepted_" .. quest_id,
                action = { type = "accept_quest", quest_id = quest_id },
                _is_quest_action = true  -- Always show as unread
            },
            {
                text = locale:t("quest.decline"),
                next = dlg.decline_response or "end",
                _is_quest_action = true  -- Always show as unread
            }
        }
    }

    -- Create acceptance response virtual node (persistent)
    dialogue.current_tree.nodes["quest_accepted_" .. quest_id] = {
        text = accept_text,
        speaker = speaker,
        choices = {
            { text = locale:t("common.continue"), next = dlg.decline_response or "end", _is_quest_action = true }
        }
    }

    return virtual_node
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function core:initialize(dialogue, display_module)
    -- Set dialogue font (will be scaled by virtual coordinates)
    -- Use locale font for Korean support
    core.font = locale:getFont("option") or love.graphics.newFont(18)

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
    dialogue.choice_font = locale:getFont("option") or love.graphics.newFont(16)

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
    dialogue.showing_single_text = false

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

    -- Typewriter effect state
    dialogue.typewriter_position = 0       -- Current character position
    dialogue.typewriter_complete = true    -- Is typing finished?
    dialogue.typewriter_speed = 0.03       -- Seconds per character (fast)
    dialogue.typewriter_sound_interval = 3 -- Play sound every N characters
    dialogue.typewriter_last_sound_pos = 0 -- Last position sound was played
    dialogue.typing_sound = "dialogue_typing" -- Default typing sound (can be per-NPC)

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
    local dialogue_tree = dialogue.dialogue_registry[dialogue_id]
    if not dialogue_tree then
        return
    end
    -- Store dialogue ID for persistence
    dialogue.current_dialogue_id = dialogue_id
    -- Store NPC object for transformations
    dialogue.current_npc = npc_obj

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

    -- Reset forced_closed flag (allowing dialogue to open)
    dialogue.forced_closed = false

    -- Store NPC ID for quest lookups (if provided)
    dialogue.current_npc_id = dialogue_tree.npc_id

    -- Set typing sound from dialogue tree (per-NPC/voice support)
    -- Format in dialogue tree: typing_sound = "dialogue_typing_female"
    dialogue.typing_sound = dialogue_tree.typing_sound or "dialogue_typing"

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
        local result = self:handleQuestOffer(dialogue, node)
        if result == "clear" then
            self:clear(dialogue)
            return
        elseif result == "redirect" then
            return
        elseif result then
            node = result  -- Virtual node returned
        end
    end

    -- Check if node has pages (multi-page dialogue)
    local pages = nil
    if node.pages_key and #node.pages_key > 0 then
        -- Translate page keys
        pages = {}
        for _, page_key in ipairs(node.pages_key) do
            table.insert(pages, resolveTextKey(page_key, page_key))
        end
    elseif node.pages and #node.pages > 0 then
        pages = node.pages
    end

    if pages and #pages > 0 then
        -- Paged mode: store pages and start at page 0
        dialogue.current_pages = pages
        dialogue.current_page_index = 0
        dialogue.total_pages = #pages
        dialogue.showing_paged_text = true
        dialogue.showing_single_text = false

        -- Reset typewriter for paged mode
        dialogue.typewriter_position = 0
        dialogue.typewriter_complete = false
        dialogue.typewriter_last_sound_pos = 0
    elseif node.choices and #node.choices > 0 then
        -- Node has choices: show custom dialogue box directly
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0
        dialogue.showing_paged_text = false
        dialogue.showing_single_text = false

        -- Reset typewriter for choices mode
        dialogue.typewriter_position = 0
        dialogue.typewriter_complete = false
        dialogue.typewriter_last_sound_pos = 0
    else
        -- Single text mode (no choices, no pages): use custom typewriter
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0
        dialogue.showing_paged_text = false
        dialogue.showing_single_text = true  -- Flag for single text mode

        -- Reset typewriter for single text mode
        dialogue.typewriter_position = 0
        dialogue.typewriter_complete = false
        dialogue.typewriter_last_sound_pos = 0
    end

    -- Store resolved speaker and text for rendering (choices mode needs it)
    dialogue.current_speaker = resolveTextKey(node.speaker_key, node.speaker, "???")
    dialogue.current_text = resolveTextKey(node.text_key, node.text)

    -- Setup choices (if any) - with conditional filtering
    if node.choices and #node.choices > 0 then
        -- Translate choices first
        local translated_choices = translateChoices(node.choices)

        -- Filter choices based on conditions
        local helpers = require "engine.ui.dialogue.helpers"
        local filtered_choices = helpers:filterChoicesByCondition(
            dialogue,
            translated_choices,
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
        -- If typewriter is still typing, skip to end
        if not dialogue.typewriter_complete then
            dialogue.typewriter_complete = true
            local current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
            dialogue.typewriter_position = utf8.len(current_text) or 0
            return
        end

        -- Advance to next page
        if dialogue.current_page_index < dialogue.total_pages - 1 then
            dialogue.current_page_index = dialogue.current_page_index + 1
            -- Reset typewriter for new page
            dialogue.typewriter_position = 0
            dialogue.typewriter_complete = false
            dialogue.typewriter_last_sound_pos = 0
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

    -- SINGLE TEXT MODE: Handle typewriter skip or advance
    if dialogue.showing_single_text then
        -- If typewriter is still typing, skip to end
        if not dialogue.typewriter_complete then
            dialogue.typewriter_complete = true
            dialogue.typewriter_position = utf8.len(dialogue.current_text or "") or 0
            return
        end
        -- Typewriter complete, advance to next node or end
        dialogue.showing_single_text = false
        if node.next then
            self:showNode(dialogue, node.next)
        else
            self:clear(dialogue)
        end
        return
    end

    -- Check for pending choices (text was shown, now show choices)
    if dialogue.pending_choices then
        dialogue.current_choices = dialogue.pending_choices
        dialogue.pending_choices = nil
        local render = require "engine.ui.dialogue.render"
        render:updateButtonVisibility(dialogue)  -- Hide buttons when choices shown
        return
    end

    -- If node has choices, handle typewriter skip or wait for selection
    if dialogue.current_choices and #dialogue.current_choices > 0 then
        -- If typewriter is still typing, skip to end
        if not dialogue.typewriter_complete then
            dialogue.typewriter_complete = true
            dialogue.typewriter_position = utf8.len(dialogue.current_text or "") or 0
        end
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
    -- Exception: Don't mark "Other quest?" related choices as selected (should remain available)
    local is_other_quest = choice.text_key == "dialogue.villager_01.choice_other_quest"
    if not is_other_quest then
        -- Use text_key for persistence if available, fallback to text
        local choice_identifier = choice.text_key or choice.text
        local choice_key = dialogue.current_node_id .. "|" .. choice_identifier
        dialogue.selected_choices[choice_key] = true

        -- Note: dialogue.selected_choices is already a reference to
        -- dialogue.all_dialogue_choices[dialogue.current_dialogue_id]
        -- so no need to update global storage separately
    end

    -- Execute choice action(s) (if any)
    local helpers = require "engine.ui.dialogue.helpers"
    if choice.actions then
        for _, action in ipairs(choice.actions) do
            helpers:executeAction(dialogue, action)
        end
    elseif choice.action then
        helpers:executeAction(dialogue, choice.action)
    end

    -- Execute on_select callback (for custom game logic like NPC→Enemy transformation)
    if choice.on_select and dialogue.game_context then
        choice.on_select(dialogue.game_context)
    end

    -- Navigate to next node
    if choice.next then
        -- Clear current state before navigating
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

    -- Don't allow navigation while typewriter is active
    if not dialogue.typewriter_complete then
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

-- Show simple dialogue (single message)
-- typing_sound: optional custom typing sound (e.g., "dialogue_typing_narrator")
function core:showSimple(dialogue, npc_name, message, typing_sound)
    dialogue.forced_closed = false  -- Reset forced_closed (allowing dialogue to open)
    dialogue.tree_mode = false  -- Disable tree mode
    dialogue.current_choices = nil  -- No choices

    -- Set typing sound (per-speaker support)
    dialogue.typing_sound = typing_sound or "dialogue_typing"

    -- Use paged mode with single page for custom typewriter
    dialogue.current_pages = { message }
    dialogue.current_page_index = 0
    dialogue.total_pages = 1
    dialogue.showing_paged_text = true
    dialogue.showing_single_text = false
    dialogue.current_speaker = npc_name or ""
    dialogue.current_text = message

    -- Reset typewriter
    dialogue.typewriter_position = 0
    dialogue.typewriter_complete = false
    dialogue.typewriter_last_sound_pos = 0

    -- Update button visibility (event-based, not polling)
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- Show multiple messages in sequence
-- typing_sound: optional custom typing sound (e.g., "dialogue_typing_narrator")
function core:showMultiple(dialogue, npc_name, messages, typing_sound)
    dialogue.forced_closed = false  -- Reset forced_closed (allowing dialogue to open)
    dialogue.tree_mode = false  -- Disable tree mode
    dialogue.current_choices = nil  -- No choices

    -- Set typing sound (per-speaker support)
    dialogue.typing_sound = typing_sound or "dialogue_typing"

    -- Use paged mode for custom typewriter
    dialogue.current_pages = messages
    dialogue.current_page_index = 0
    dialogue.total_pages = #messages
    dialogue.showing_paged_text = true
    dialogue.showing_single_text = false
    dialogue.current_speaker = npc_name or ""
    dialogue.current_text = messages[1] or ""

    -- Reset typewriter
    dialogue.typewriter_position = 0
    dialogue.typewriter_complete = false
    dialogue.typewriter_last_sound_pos = 0

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
    -- Check: tree mode, paged text (simple/multiple), or single text
    return dialogue.tree_mode or dialogue.showing_paged_text or dialogue.showing_single_text
end

function core:update(dialogue, dt)
    -- Update button visibility each frame
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)

    -- Update typewriter effect (for paged text and choices mode)
    if not dialogue.typewriter_complete then
        local current_text = dialogue.current_text or ""
        if dialogue.showing_paged_text and dialogue.current_pages then
            current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
        end
        local text_length = utf8.len(current_text) or 0
        local prev_pos = math.floor(dialogue.typewriter_position)
        dialogue.typewriter_position = dialogue.typewriter_position + (dt / dialogue.typewriter_speed)
        local new_pos = math.floor(dialogue.typewriter_position)

        -- Play typing sound at intervals (skip if typing_sound is "none" or "")
        if new_pos > prev_pos and dialogue.typing_sound and dialogue.typing_sound ~= "" and dialogue.typing_sound ~= "none" then
            local sound_pos = math.floor(new_pos / dialogue.typewriter_sound_interval)
            local last_sound_pos = math.floor(dialogue.typewriter_last_sound_pos / dialogue.typewriter_sound_interval)
            if sound_pos > last_sound_pos then
                local sound_sys = require "engine.core.sound"
                sound_sys:playSFX("ui", dialogue.typing_sound)
                dialogue.typewriter_last_sound_pos = new_pos
            end
        end

        if dialogue.typewriter_position >= text_length then
            dialogue.typewriter_position = text_length
            dialogue.typewriter_complete = true
        end
    end

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
            -- If typewriter is still typing, skip to end first
            if not dialogue.typewriter_complete then
                dialogue.typewriter_complete = true
                dialogue.typewriter_position = utf8.len(dialogue.current_text or "") or 0
                return  -- Don't select yet, just show full text
            end
            self:selectChoice(dialogue, dialogue.selected_choice_index)
        else
            -- No choices - advance tree
            self:advanceTree(dialogue)
        end
    else
        -- Simple dialogue mode (showSimple/showMultiple): handle paged text
        if dialogue.showing_paged_text and dialogue.current_pages then
            -- If typewriter is still typing, skip to end
            if not dialogue.typewriter_complete then
                dialogue.typewriter_complete = true
                local current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
                dialogue.typewriter_position = utf8.len(current_text) or 0
                return
            end

            -- Advance to next page
            if dialogue.current_page_index < dialogue.total_pages - 1 then
                dialogue.current_page_index = dialogue.current_page_index + 1
                -- Update current_text for typewriter
                dialogue.current_text = dialogue.current_pages[dialogue.current_page_index + 1] or ""
                -- Reset typewriter for new page
                dialogue.typewriter_position = 0
                dialogue.typewriter_complete = false
                dialogue.typewriter_last_sound_pos = 0
                return
            else
                -- Last page reached - close dialogue
                self:clear(dialogue)
            end
        end

        -- Update button visibility
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
    dialogue.showing_single_text = false

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

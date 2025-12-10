-- engine/ui/dialogue/tree.lua
-- Dialogue tree system: branching conversations with choices

local utf8 = require "utf8"
local locale = require "engine.core.locale"

local tree = {}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Helper: Resolve text from localization key or direct value
local function resolveTextKey(key, fallback, default)
    default = default or ""
    if not key then return fallback or default end

    local translated = locale:t(key)
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

-- ============================================================================
-- QUEST OFFER HANDLING
-- ============================================================================

-- Handle quest_offer node type (dynamic quest dialogue generation)
-- Returns: virtual_node table, "clear", "redirect", or nil
function tree:handleQuestOffer(dialogue, node)
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
                _is_quest_action = true
            },
            {
                text = locale:t("quest.decline"),
                next = dlg.decline_response or "end",
                _is_quest_action = true
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
-- TREE MANAGEMENT
-- ============================================================================

-- Start a dialogue tree by ID (loads from registry)
function tree:showTreeById(dialogue, dialogue_id, npc_id, npc_obj)
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
        self:showTree(dialogue, tree_copy)
    else
        self:showTree(dialogue, dialogue_tree)
    end
end

-- Start a dialogue tree (choice-based conversation)
function tree:showTree(dialogue, dialogue_tree)
    if not dialogue_tree or not dialogue_tree.nodes then
        return
    end

    -- Reset forced_closed flag (allowing dialogue to open)
    dialogue.forced_closed = false

    -- Store NPC ID for quest lookups (if provided)
    dialogue.current_npc_id = dialogue_tree.npc_id

    -- Set typing sound from dialogue tree (per-NPC/voice support)
    dialogue.typing_sound = dialogue_tree.typing_sound or "dialogue_typing"

    -- Load selected choices for this dialogue (instead of resetting)
    if dialogue.current_dialogue_id then
        if not dialogue.all_dialogue_choices[dialogue.current_dialogue_id] then
            dialogue.all_dialogue_choices[dialogue.current_dialogue_id] = {}
        end
        dialogue.selected_choices = dialogue.all_dialogue_choices[dialogue.current_dialogue_id]
    else
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
function tree:showNode(dialogue, node_id)
    local typewriter = require "engine.ui.dialogue.typewriter"

    local node = dialogue.current_tree.nodes[node_id]
    if not node then
        local core = require "engine.ui.dialogue.core"
        core:clear(dialogue)
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
            self:showNode(dialogue, redirect_node)
            return
        end
    end

    -- Check for quest_offer node type
    if node.type == "quest_offer" then
        local result = self:handleQuestOffer(dialogue, node)
        if result == "clear" then
            local core = require "engine.ui.dialogue.core"
            core:clear(dialogue)
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
        pages = {}
        for _, page_key in ipairs(node.pages_key) do
            table.insert(pages, resolveTextKey(page_key, page_key))
        end
    elseif node.pages and #node.pages > 0 then
        pages = node.pages
    end

    if pages and #pages > 0 then
        -- Paged mode
        dialogue.current_pages = pages
        dialogue.current_page_index = 0
        dialogue.total_pages = #pages
        dialogue.showing_paged_text = true
        dialogue.showing_single_text = false
        typewriter:reset(dialogue)
    elseif node.choices and #node.choices > 0 then
        -- Choices mode
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0
        dialogue.showing_paged_text = false
        dialogue.showing_single_text = false
        typewriter:reset(dialogue)
    else
        -- Single text mode
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0
        dialogue.showing_paged_text = false
        dialogue.showing_single_text = true
        typewriter:reset(dialogue)
    end

    -- Store resolved speaker and text for rendering
    dialogue.current_speaker = resolveTextKey(node.speaker_key, node.speaker, "???")
    dialogue.current_text = resolveTextKey(node.text_key, node.text)

    -- Setup choices (if any) - with conditional filtering
    if node.choices and #node.choices > 0 then
        local translated_choices = translateChoices(node.choices)

        local helpers = require "engine.ui.dialogue.helpers"
        local filtered_choices = helpers:filterChoicesByCondition(
            dialogue,
            translated_choices,
            dialogue.current_dialogue_id,
            dialogue.current_node_id
        )

        if #filtered_choices > 0 then
            if dialogue.showing_paged_text then
                dialogue.pending_choices = filtered_choices
                dialogue.current_choices = nil
            else
                dialogue.current_choices = filtered_choices
                dialogue.pending_choices = nil
            end
            dialogue.selected_choice_index = 1
        else
            dialogue.current_choices = nil
            dialogue.pending_choices = nil
            dialogue.selected_choice_index = 1
        end
    else
        dialogue.current_choices = nil
        dialogue.pending_choices = nil
        dialogue.selected_choice_index = 1
    end

    -- Store current node for rendering
    dialogue.current_node = node

    -- Execute node action (if any)
    if node.action then
        local helpers = require "engine.ui.dialogue.helpers"
        helpers:executeAction(dialogue, node.action)
    end

    -- Update button visibility
    local render = require "engine.ui.dialogue.render"
    render:updateButtonVisibility(dialogue)
end

-- Advance dialogue tree
function tree:advanceTree(dialogue)
    local typewriter = require "engine.ui.dialogue.typewriter"

    if not dialogue.tree_mode then
        return
    end

    local node = dialogue.current_tree.nodes[dialogue.current_node_id]
    if not node then
        local core = require "engine.ui.dialogue.core"
        core:clear(dialogue)
        return
    end

    -- PAGED MODE: Handle page navigation
    if dialogue.showing_paged_text and dialogue.current_pages then
        if not dialogue.typewriter_complete then
            typewriter:skip(dialogue)
            return
        end

        if dialogue.current_page_index < dialogue.total_pages - 1 then
            dialogue.current_page_index = dialogue.current_page_index + 1
            typewriter:reset(dialogue)
            return
        else
            if dialogue.pending_choices and #dialogue.pending_choices > 0 then
                dialogue.current_choices = dialogue.pending_choices
                dialogue.pending_choices = nil
                dialogue.selected_choice_index = 1
                return
            elseif dialogue.current_choices and #dialogue.current_choices > 0 then
                return
            else
                if node.next then
                    self:showNode(dialogue, node.next)
                else
                    local core = require "engine.ui.dialogue.core"
                    core:clear(dialogue)
                end
                return
            end
        end
    end

    -- SINGLE TEXT MODE
    if dialogue.showing_single_text then
        if not dialogue.typewriter_complete then
            typewriter:skip(dialogue)
            return
        end
        dialogue.showing_single_text = false
        if node.next then
            self:showNode(dialogue, node.next)
        else
            local core = require "engine.ui.dialogue.core"
            core:clear(dialogue)
        end
        return
    end

    -- Check for pending choices
    if dialogue.pending_choices then
        dialogue.current_choices = dialogue.pending_choices
        dialogue.pending_choices = nil
        local render = require "engine.ui.dialogue.render"
        render:updateButtonVisibility(dialogue)
        return
    end

    -- If node has choices, handle typewriter skip
    if dialogue.current_choices and #dialogue.current_choices > 0 then
        if not dialogue.typewriter_complete then
            typewriter:skip(dialogue)
        end
        return
    end

    -- No choices - check for auto-advance
    if node.next then
        self:showNode(dialogue, node.next)
    else
        local core = require "engine.ui.dialogue.core"
        core:clear(dialogue)
    end
end

-- ============================================================================
-- CHOICE HANDLING
-- ============================================================================

-- Select a choice (keyboard/gamepad navigation)
function tree:selectChoice(dialogue, choice_index)
    if not dialogue.tree_mode or not dialogue.current_choices then
        return
    end

    local choice = dialogue.current_choices[choice_index]
    if not choice then
        return
    end

    if choice._is_disabled then
        return
    end

    -- Mark this choice as selected (for grey-out effect)
    local is_other_quest = choice.text_key == "dialogue.villager_01.choice_other_quest"
    if not is_other_quest then
        local choice_identifier = choice.text_key or choice.text
        local choice_key = dialogue.current_node_id .. "|" .. choice_identifier
        dialogue.selected_choices[choice_key] = true
    end

    -- Execute choice action(s)
    local helpers = require "engine.ui.dialogue.helpers"
    if choice.actions then
        for _, action in ipairs(choice.actions) do
            helpers:executeAction(dialogue, action)
        end
    elseif choice.action then
        helpers:executeAction(dialogue, choice.action)
    end

    -- Execute on_select callback
    if choice.on_select and dialogue.game_context then
        choice.on_select(dialogue.game_context)
    end

    -- Navigate to next node
    if choice.next then
        dialogue.showing_paged_text = false
        dialogue.current_pages = nil
        dialogue.current_page_index = 0
        dialogue.total_pages = 0

        self:showNode(dialogue, choice.next)
    else
        local core = require "engine.ui.dialogue.core"
        core:clear(dialogue)
    end
end

-- Navigate choice selection (keyboard/gamepad)
function tree:moveChoiceSelection(dialogue, direction)
    if not dialogue.tree_mode or not dialogue.current_choices then
        return
    end

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

return tree

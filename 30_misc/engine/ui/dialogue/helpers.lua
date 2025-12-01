-- engine/ui/dialogue/helpers.lua
-- Dialogue helper functions: input, flags, history, actions

local Talkies = require "vendor.talkies"
local coords = require "engine.core.coords"

local helpers = {}

-- ============================================================================
-- INPUT HANDLING
-- ============================================================================

-- Get choice index at position (for mouse/touch click)
-- Returns choice index (1-based) or nil if no choice at position
function helpers:getChoiceAtPosition(dialogue, x, y)
    if not dialogue.display or not dialogue.current_choices or #dialogue.current_choices == 0 then
        return nil
    end

    -- Convert physical coordinates to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, dialogue.display)

    local vw, vh = dialogue.display:GetVirtualDimensions()
    local choice_count = #dialogue.current_choices
    local choice_height = 35  -- Same as render:drawChoices
    local choice_spacing = 8  -- Same as render:drawChoices

    -- Calculate dialogue box dimensions
    local padding = 10
    local font = Talkies.font or love.graphics.getFont()
    local extra_height = font:getHeight() * 1.5
    local boxH = vh * 0.4 - (2 * padding) + extra_height
    local boxY = vh - (boxH + padding)

    -- Choice width and positioning (1/2 screen width)
    local choice_width = (vw * 1 / 2) - (2 * padding)
    local total_height = (choice_height * choice_count) + (choice_spacing * (choice_count - 1))

    -- Position choices: bottom-right corner
    local start_x = vw - choice_width - (2 * padding)
    local start_y = vh - total_height - (2 * padding)

    -- Check each choice button
    for i = 1, choice_count do
        local btn_y = start_y + ((i - 1) * (choice_height + choice_spacing))

        if vx >= start_x and vx <= start_x + choice_width and
           vy >= btn_y and vy <= btn_y + choice_height then
            return i
        end
    end

    return nil
end

-- Handle touch/mouse press on buttons and choices
function helpers:touchPressed(dialogue, id, x, y)
    if not dialogue:isOpen() then
        return false
    end

    -- Priority 1: Check choice buttons (if visible)
    if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
        local choice_index = self:getChoiceAtPosition(dialogue, x, y)
        if choice_index then
            -- Highlight the choice being pressed AND remember which one
            dialogue.selected_choice_index = choice_index
            dialogue.pressed_choice_index = choice_index
            return true
        end
    end

    -- Priority 2: NEXT button (left of SKIP)
    if dialogue.next_button and dialogue.next_button:touchPressed(id, x, y) then
        return true  -- Consumed by next button
    end

    -- Priority 3: SKIP button
    if dialogue.skip_button and dialogue.skip_button:touchPressed(id, x, y) then
        return true  -- Consumed by skip button
    end

    return false
end

-- Handle touch/mouse release on buttons and choices
function helpers:touchReleased(dialogue, id, x, y)
    -- Always process button releases even if dialogue closed
    -- (to clean up button pressed state)
    local button_consumed = false

    -- Priority 1: NEXT button - advances to next message
    if dialogue.next_button and dialogue.next_button:touchReleased(id, x, y) then
        if dialogue:isOpen() then
            dialogue:onAction()  -- Advance dialogue (only if still open)
        end
        button_consumed = true
    end

    -- Priority 2: SKIP button - clears all dialogue (only if fully charged)
    if dialogue.skip_button and dialogue.skip_button:touchReleased(id, x, y) then
        if dialogue:isOpen() then
            -- touchReleased returns true only if fully charged
            dialogue:clear()  -- Clear all dialogue
        end
        button_consumed = true
    end

    if button_consumed then
        return true
    end

    -- Early exit if dialogue is closed (after button processing)
    if not dialogue:isOpen() then
        return false
    end

    -- Priority 3: Check choice buttons (if visible)
    if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
        local choice_index = self:getChoiceAtPosition(dialogue, x, y)
        -- Only select if released on the SAME choice that was pressed (prevent click-through)
        if choice_index and choice_index == dialogue.pressed_choice_index then
            -- Select the clicked choice
            dialogue:selectChoice(choice_index)
            dialogue.pressed_choice_index = nil  -- Reset
            return true
        end
        -- Reset even if released on a different choice
        dialogue.pressed_choice_index = nil
    end

    return false
end

-- Handle touch/mouse move
function helpers:touchMoved(dialogue, id, x, y)
    if dialogue:isOpen() then
        -- Check for choice hover (mouse/touch move)
        if dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0 then
            local hover_index = self:getChoiceAtPosition(dialogue, x, y)
            if hover_index then
                dialogue.selected_choice_index = hover_index
            end
        end

        if dialogue.skip_button then
            dialogue.skip_button:touchMoved(id, x, y)
        end
        if dialogue.next_button then
            dialogue.next_button:touchMoved(id, x, y)
        end
    end
end

-- ============================================================================
-- PERSISTENCE SYSTEM (History)
-- ============================================================================

-- Export dialogue choice history (for save system)
function helpers:exportChoiceHistory(dialogue)
    return dialogue.all_dialogue_choices
end

-- Import dialogue choice history (from save file)
function helpers:importChoiceHistory(dialogue, history)
    if not history then
        return
    end

    -- Ensure all_dialogue_choices exists (in case called before initialize)
    if not dialogue.all_dialogue_choices then
        dialogue.all_dialogue_choices = {}
    end

    -- Merge loaded history with current state
    for dialogue_id, choices in pairs(history) do
        if not dialogue.all_dialogue_choices[dialogue_id] then
            dialogue.all_dialogue_choices[dialogue_id] = {}
        end
        for choice_key, value in pairs(choices) do
            dialogue.all_dialogue_choices[dialogue_id][choice_key] = value
        end
    end
end

-- Clear all dialogue history (for new game)
function helpers:clearAllHistory(dialogue)
    dialogue.all_dialogue_choices = {}
    dialogue.selected_choices = {}
    dialogue.current_dialogue_id = nil
end

-- Clear history for a specific dialogue (optional utility)
function helpers:clearDialogueHistory(dialogue, dialogue_id)
    if dialogue.all_dialogue_choices[dialogue_id] then
        dialogue.all_dialogue_choices[dialogue_id] = nil
    end

    -- If this is the current dialogue, also clear local state
    if dialogue.current_dialogue_id == dialogue_id then
        dialogue.selected_choices = {}
    end
end

-- ============================================================================
-- ACTION SYSTEM
-- ============================================================================

-- Execute action from dialogue choice
function helpers:executeAction(dialogue, action)
    if not action then
        return
    end

    -- Handle set_flag field (can be combined with other actions)
    if action.set_flag then
        self:setFlag(dialogue, dialogue.current_dialogue_id, action.set_flag.flag, action.set_flag.value)
    end

    -- Early exit if no type specified
    if not action.type then
        return
    end

    -- Quest actions
    if action.type == "accept_quest" then
        if dialogue.quest_system and action.quest_id then
            dialogue.quest_system:accept(action.quest_id)
        end
    elseif action.type == "complete_quest" or action.type == "turn_in_quest" then
        if dialogue.quest_system and action.quest_id then
            local success, rewards = dialogue.quest_system:turnIn(action.quest_id)
            if success then
                -- Could trigger reward notification here
            end
        end
    elseif action.type == "set_flag" then
        -- Standalone set_flag action
        if action.flag then
            self:setFlag(dialogue, dialogue.current_dialogue_id, action.flag, action.value)
        end
    elseif action.type == "transform_to_enemy" then
        -- NPC → Enemy transformation
        if dialogue.world and dialogue.current_npc and action.enemy_type then
            local success = dialogue.world:transformNPCToEnemy(dialogue.current_npc, action.enemy_type)
            if success then
                -- Close dialogue immediately after transformation
                dialogue.active = false
            end
        end
    -- Add more action types as needed:
    -- elseif action.type == "give_item" then
    --     -- inventory:addItem(action.item_id, action.count)
    -- elseif action.type == "remove_item" then
    --     -- inventory:removeItem(action.item_id, action.count)
    -- elseif action.type == "give_gold" then
    --     -- player.gold = player.gold + action.amount
    end
end

-- ============================================================================
-- DIALOGUE FLAGS SYSTEM
-- ============================================================================

-- Set a dialogue flag
function helpers:setFlag(dialogue, dialogue_id, flag_name, value)
    if not dialogue.dialogue_flags[dialogue_id] then
        dialogue.dialogue_flags[dialogue_id] = {}
    end
    dialogue.dialogue_flags[dialogue_id][flag_name] = value
end

-- Get a dialogue flag
function helpers:getFlag(dialogue, dialogue_id, flag_name, default)
    if not dialogue.dialogue_flags[dialogue_id] then
        return default
    end
    local value = dialogue.dialogue_flags[dialogue_id][flag_name]
    return value ~= nil and value or default
end

-- Check if a flag is set
function helpers:hasFlag(dialogue, dialogue_id, flag_name)
    return dialogue.dialogue_flags[dialogue_id] and
           dialogue.dialogue_flags[dialogue_id][flag_name] ~= nil
end

-- Clear all flags for a dialogue
function helpers:clearFlags(dialogue, dialogue_id)
    dialogue.dialogue_flags[dialogue_id] = nil
end

-- Clear all flags globally
function helpers:clearAllFlags(dialogue)
    dialogue.dialogue_flags = {}
end

-- Clear all dialogue choice history (for New Game)
function helpers:clearChoiceHistory(dialogue)
    dialogue.all_dialogue_choices = {}
end

-- Evaluate a condition (function or declarative)
function helpers:evaluateCondition(condition, context)
    if not condition then
        return true  -- No condition = always show
    end

    -- Legacy function support (will be deprecated)
    if type(condition) == "function" then
        return condition(context)
    end

    -- Declarative condition types
    if type(condition) == "table" then
        local cond_type = condition.type

        -- Quest-related conditions
        if cond_type == "has_available_quests" then
            -- Check if NPC has any available quests to offer via dialogue system
            -- NOTE: Only counts quests with dialogue field (for quest_offer node)
            local quest_system = context.quest_system
            local npc_id = condition.npc_id or context.npc_id

            if not quest_system or not quest_system.quest_registry or not npc_id then
                return false
            end

            -- Get all quests offered by this NPC with dialogue (check prerequisites)
            for quest_id, quest_data in pairs(quest_system.quest_registry) do
                if quest_data.giver_npc == npc_id and quest_data.dialogue then
                    -- Use canAccept() to check prerequisites
                    if quest_system:canAccept(quest_id) then
                        return true
                    end
                end
            end
            return false

        elseif cond_type == "quest_state_is" then
            -- Check if quest is in a specific state
            local quest_system = context.quest_system
            if not quest_system or not condition.quest_id then
                return false
            end

            local state = quest_system:getState(condition.quest_id)
            return state and state.state == condition.state

        -- Flag-related conditions
        elseif cond_type == "flag_is_true" then
            -- Check if a dialogue flag is set to true
            local dialogue = context.dialogue_system
            if not dialogue or not condition.flag then
                return false
            end

            local dialogue_id = condition.dialogue_id or context.dialogue_id
            return self:getFlag(dialogue, dialogue_id, condition.flag, false) == true

        elseif cond_type == "flag_equals" then
            -- Check if a dialogue flag equals a specific value
            local dialogue = context.dialogue_system
            if not dialogue or not condition.flag then
                return false
            end

            local dialogue_id = condition.dialogue_id or context.dialogue_id
            local flag_value = self:getFlag(dialogue, dialogue_id, condition.flag, nil)
            return flag_value == condition.value

        -- Add more condition types as needed:
        -- elseif cond_type == "has_item" then
        --     return inventory:hasItem(condition.item_id, condition.count or 1)
        -- elseif cond_type == "gold_greater_than" then
        --     return player.gold >= condition.amount
        end
    end

    -- Unknown condition type - default to true for safety
    return true
end

-- Filter choices based on their conditions
function helpers:filterChoicesByCondition(dialogue, choices, dialogue_id, node_id)
    if not choices then
        return {}
    end

    local filtered = {}
    for i, choice in ipairs(choices) do
        -- Build context for condition evaluation
        local context = {
            dialogue_id = dialogue_id,
            node_id = node_id,
            choice_index = i,
            choice = choice,
            quest_system = dialogue.quest_system,
            dialogue_system = dialogue,  -- Pass dialogue system for flag access
            npc_id = dialogue.current_npc_id,  -- Current NPC for quest lookups
        }

        -- Check if choice should be shown
        if self:evaluateCondition(choice.condition, context) then
            -- Check if choice should be disabled (greyed out but visible)
            local is_disabled = false

            -- Manual disabled condition (for game-specific logic)
            if choice.disabled and self:evaluateCondition(choice.disabled, context) then
                is_disabled = true
            end

            -- NOTE: Auto-disable for quest accept removed - quest_offer node
            -- already filters by canAccept(), so Accept button should never be disabled

            -- Attach disabled flag to choice
            choice._is_disabled = is_disabled

            table.insert(filtered, choice)
        end
    end

    return filtered
end

return helpers

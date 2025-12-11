-- engine/scenes/gameplay/quest_interactions.lua
-- Quest-related NPC interaction handlers

local quest_interactions = {}

local dialogue = require "engine.ui.dialogue"
local quest_system = require "engine.core.quest"
local locale = require "engine.core.locale"
local item_class = require "engine.entities.item"

-- Helper: Resolve translation key or fallback to direct value
local function resolveText(key_field, fallback_field, default)
    if key_field then
        local translated = locale:t(key_field)
        if translated ~= key_field then
            return translated
        end
    end
    return fallback_field or default or "???"
end

-- Helper: Get translated item name
local function getItemName(item_type)
    local registry = item_class.type_registry
    if registry and registry[item_type] then
        local item_def = registry[item_type]
        if item_def.name_key then
            local translated = locale:t(item_def.name_key)
            if translated ~= item_def.name_key then
                return translated
            end
        end
        return item_def.name or item_type
    end
    return item_type
end

-- Helper: Get first completable quest for NPC
function quest_interactions.getCompletableQuest(scene, npc_id)
    for quest_id, quest_def in pairs(quest_system.quest_registry) do
        local state = quest_system:getState(quest_id)
        local receiver = quest_def.receiver_npc or quest_def.giver_npc

        if receiver == npc_id and state and state.state == quest_system.STATE.COMPLETED then
            return {
                id = quest_id,
                def = quest_def,
                state = state
            }
        end
    end

    return nil
end

-- Helper: Get first available quest for NPC
function quest_interactions.getAvailableQuest(scene, npc_id)
    for quest_id, quest_def in pairs(quest_system.quest_registry) do
        if quest_def.giver_npc == npc_id and quest_system:canAccept(quest_id) then
            local state = quest_system:getState(quest_id)
            return {
                id = quest_id,
                def = quest_def,
                state = state
            }
        end
    end

    return nil
end

-- Helper: Show quest offer dialogue (with accept/decline choices)
function quest_interactions.showQuestOfferDialogue(scene, quest_info, npc_name)
    -- Resolve translated texts
    local title = resolveText(quest_info.def.title_key, quest_info.def.title)
    local description = resolveText(quest_info.def.description_key, quest_info.def.description)

    -- Build quest description text
    local description_lines = {
        title,
        description,
        "",
        locale:t("quest.objectives") .. ":"
    }

    -- Add objectives
    for i, obj in ipairs(quest_info.def.objectives) do
        local obj_desc = resolveText(obj.description_key, obj.description)
        table.insert(description_lines, string.format("- %s", obj_desc))
    end

    -- Add rewards
    local rewards = quest_info.def.rewards or {}
    if rewards.gold or rewards.exp or (rewards.items and #rewards.items > 0) then
        table.insert(description_lines, "")
        table.insert(description_lines, locale:t("quest.rewards") .. ":")

        if rewards.gold then
            table.insert(description_lines, string.format("- %d %s", rewards.gold, locale:t("quest.reward_gold")))
        end
        if rewards.exp then
            table.insert(description_lines, string.format("- %d %s", rewards.exp, locale:t("quest.reward_exp")))
        end
        if rewards.items then
            for _, item_type in ipairs(rewards.items) do
                table.insert(description_lines, string.format("- %s", getItemName(item_type)))
            end
        end
    end

    local description_text = table.concat(description_lines, "\n")

    -- Create dialogue tree for quest offer
    local quest_tree = {
        start_node = "offer",
        nodes = {
            offer = {
                text = description_text,
                speaker = npc_name,
                choices = {
                    {
                        text = locale:t("quest.accept"),
                        next = "accepted",
                        action = {
                            type = "accept_quest",
                            quest_id = quest_info.id
                        },
                        _is_quest_action = true  -- Always show as unread
                    },
                    {
                        text = locale:t("quest.decline"),
                        next = "declined",
                        _is_quest_action = true  -- Always show as unread
                    }
                }
            },
            accepted = {
                text = locale:t("quest.accepted_message") or "Good luck on your quest!",
                speaker = npc_name,
                next = nil  -- End dialogue
            },
            declined = {
                text = locale:t("quest.declined_message") or "Come back if you change your mind.",
                speaker = npc_name,
                next = nil  -- End dialogue
            }
        }
    }

    -- Show dialogue tree
    dialogue:showTree(quest_tree)
end

-- Helper: Process delivery quests when talking to NPC
function quest_interactions.processDeliveryQuests(scene, npc_id)
    -- Check all active quests for deliveries to this NPC
    for quest_id, quest_def in pairs(quest_system.quest_registry) do
        local state = quest_system:getState(quest_id)

        if state and state.state == quest_system.STATE.ACTIVE then
            -- Check each objective
            for obj_idx, obj in ipairs(quest_def.objectives) do
                if obj.type == quest_system.TYPE.DELIVER and obj.npc == npc_id then
                    -- Check if player has the required item
                    local item_type = obj.target
                    local has_item = scene.inventory:hasItem(item_type)

                    if has_item then
                        -- Remove item from inventory
                        scene.inventory:removeItemByType(item_type, 1)

                        -- Track delivery progress
                        quest_system:onItemDelivered(item_type, npc_id)
                    end
                end
            end
        end
    end
end

-- Helper: Process pickup quests when talking to NPC
-- Returns true if pickup occurred (to show dialogue), false otherwise
function quest_interactions.processPickupQuests(scene, npc_id)
    local pickup_quest_id, item_type, count = quest_system:getActivePickupQuest(npc_id)

    if pickup_quest_id and item_type then
        -- Add item to inventory
        local success = scene.inventory:addItem(item_type, count)

        if success then
            -- Track pickup progress
            quest_system:onItemPickedUp(item_type, npc_id)
            return true, item_type, count
        end
    end

    return false, nil, nil
end

-- Helper: Show quest turn-in dialogue
function quest_interactions.showQuestTurnInDialogue(scene, quest_info, npc_name)
    -- Turn in quest and get rewards (gold/exp handled by quest_system callback)
    local success, rewards = quest_system:turnIn(quest_info.id)

    if not success then
        return
    end

    -- Ensure rewards is a table (may be nil if quest has no rewards)
    rewards = rewards or {}

    -- Resolve translated texts
    local title = resolveText(quest_info.def.title_key, quest_info.def.title)
    local description = resolveText(quest_info.def.description_key, quest_info.def.description)

    -- Add items to inventory (not handled by callback)
    if rewards.items then
        for _, item_type in ipairs(rewards.items) do
            scene.inventory:addItem(item_type, 1)
        end
    end

    -- Build rewards text for dialogue
    local rewards_text = locale:t("quest.rewards") .. ": "
    local reward_parts = {}

    if rewards.gold then
        table.insert(reward_parts, rewards.gold .. " " .. locale:t("quest.reward_gold"))
    end
    if rewards.exp then
        table.insert(reward_parts, rewards.exp .. " " .. locale:t("quest.reward_exp"))
    end
    if rewards.items then
        for _, item_type in ipairs(rewards.items) do
            table.insert(reward_parts, getItemName(item_type))
        end
    end

    if #reward_parts > 0 then
        rewards_text = rewards_text .. table.concat(reward_parts, ", ")
    else
        rewards_text = locale:t("quest.thank_you") or "Thank you!"
    end

    -- Show dialogue
    local messages = {
        locale:t("quest.complete") .. ": " .. title,
        description,
        rewards_text
    }

    dialogue:showMultiple(npc_name, messages)
end

return quest_interactions

-- engine/scenes/gameplay/quest_interactions.lua
-- Quest-related NPC interaction handlers

local quest_interactions = {}

local dialogue = require "engine.ui.dialogue"
local quest_system = require "engine.core.quest"

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
    -- Build quest description text
    local description_lines = {
        quest_info.def.title,
        quest_info.def.description,
        "",
        "Objectives:"
    }

    -- Add objectives
    for i, obj in ipairs(quest_info.def.objectives) do
        table.insert(description_lines, string.format("- %s", obj.description))
    end

    -- Add rewards
    local rewards = quest_info.def.rewards or {}
    if rewards.gold or rewards.exp or (rewards.items and #rewards.items > 0) then
        table.insert(description_lines, "")
        table.insert(description_lines, "Rewards:")

        if rewards.gold then
            table.insert(description_lines, string.format("- %d Gold", rewards.gold))
        end
        if rewards.exp then
            table.insert(description_lines, string.format("- %d EXP", rewards.exp))
        end
        if rewards.items then
            for _, item in ipairs(rewards.items) do
                table.insert(description_lines, string.format("- %s", item))
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
                        text = "Accept Quest",
                        next = "accepted",
                        action = {
                            type = "accept_quest",
                            quest_id = quest_info.id
                        }
                    },
                    {
                        text = "Decline",
                        next = "declined"
                    }
                }
            },
            accepted = {
                text = "Good luck on your quest!",
                speaker = npc_name,
                next = nil  -- End dialogue
            },
            declined = {
                text = "Come back if you change your mind.",
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

-- Helper: Show quest turn-in dialogue
function quest_interactions.showQuestTurnInDialogue(scene, quest_info, npc_name)
    -- Turn in quest and get rewards (gold/exp handled by quest_system callback)
    local success, rewards = quest_system:turnIn(quest_info.id)

    if not success then
        return
    end

    -- Add items to inventory (not handled by callback)
    if rewards.items then
        for _, item_type in ipairs(rewards.items) do
            scene.inventory:addItem(item_type, 1)
        end
    end

    -- Build rewards text for dialogue
    local rewards_text = "Rewards: "
    local reward_parts = {}

    if rewards.gold then
        table.insert(reward_parts, rewards.gold .. " gold")
    end
    if rewards.exp then
        table.insert(reward_parts, rewards.exp .. " exp")
    end
    if rewards.items then
        for _, item in ipairs(rewards.items) do
            table.insert(reward_parts, item)
        end
    end

    if #reward_parts > 0 then
        rewards_text = rewards_text .. table.concat(reward_parts, ", ")
    else
        rewards_text = "Thank you!"
    end

    -- Show dialogue
    local messages = {
        "Quest Complete: " .. quest_info.def.title,
        quest_info.def.description,
        rewards_text
    }

    dialogue:showMultiple(npc_name, messages)
end

return quest_interactions

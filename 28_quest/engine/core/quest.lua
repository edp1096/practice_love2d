-- engine/core/quest.lua
-- Quest system core (100% reusable)
-- Supports: kill, collect, talk, explore, deliver quests

local quest = {}

-- Quest states
quest.STATE = {
    AVAILABLE = "available",  -- Can be accepted from NPC
    ACTIVE = "active",        -- Currently in progress
    COMPLETED = "completed",  -- Objectives done, ready to turn in
    TURNED_IN = "turned_in"   -- Turned in to NPC, rewards claimed
}

-- Objective types
quest.TYPE = {
    KILL = "kill",           -- Kill N enemies of type X
    COLLECT = "collect",     -- Collect N items of type X
    TALK = "talk",           -- Talk to NPC X
    EXPLORE = "explore",     -- Visit location X
    DELIVER = "deliver"      -- Deliver item X to NPC Y
}

function quest:init()
    -- Quest registry (injected from game data)
    self.quest_registry = {}

    -- Active quest states (runtime)
    -- Format: { quest_id = { state, objectives, ... } }
    self.quest_states = {}

    -- Quest callbacks (for progress tracking)
    self.callbacks = {
        on_quest_accepted = nil,    -- function(quest_id)
        on_quest_completed = nil,   -- function(quest_id)
        on_quest_turned_in = nil,   -- function(quest_id, rewards)
        on_objective_updated = nil  -- function(quest_id, objective_index, current, target)
    }
end

-- Register quest definitions (called from main.lua with game data)
function quest:registerQuests(quest_data)
    for id, data in pairs(quest_data) do
        self.quest_registry[id] = self:_cloneQuestData(data)
        -- Initialize state if not exists
        if not self.quest_states[id] then
            self.quest_states[id] = {
                state = self.STATE.AVAILABLE,
                objectives = self:_initObjectives(data.objectives)
            }
        end
    end
end

-- Deep clone quest data (prevent mutation)
function quest:_cloneQuestData(data)
    local clone = {
        id = data.id,
        title = data.title,
        description = data.description,
        objectives = {},
        giver_npc = data.giver_npc,
        receiver_npc = data.receiver_npc or data.giver_npc,  -- Default to giver
        rewards = data.rewards and {
            gold = data.rewards.gold,
            exp = data.rewards.exp,
            items = data.rewards.items and {unpack(data.rewards.items)} or {}
        } or {},
        prerequisites = data.prerequisites and {unpack(data.prerequisites)} or {}
    }

    for i, obj in ipairs(data.objectives) do
        clone.objectives[i] = {
            type = obj.type,
            target = obj.target,
            count = obj.count or 1,
            description = obj.description
        }
    end

    return clone
end

-- Initialize objective progress
function quest:_initObjectives(objectives)
    local progress = {}
    for i, obj in ipairs(objectives) do
        progress[i] = {
            current = 0,
            target = obj.count or 1,
            completed = false
        }
    end
    return progress
end

-- Check if quest can be accepted
function quest:canAccept(quest_id)
    local def = self.quest_registry[quest_id]
    if not def then return false end

    local state = self.quest_states[quest_id]
    if not state or state.state ~= self.STATE.AVAILABLE then
        return false
    end

    -- Check prerequisites
    if def.prerequisites then
        for _, prereq_id in ipairs(def.prerequisites) do
            local prereq_state = self.quest_states[prereq_id]
            if not prereq_state or prereq_state.state ~= self.STATE.TURNED_IN then
                return false
            end
        end
    end

    return true
end

-- Accept quest
function quest:accept(quest_id)
    if not self:canAccept(quest_id) then
        return false
    end

    local state = self.quest_states[quest_id]
    state.state = self.STATE.ACTIVE

    -- Trigger callback
    if self.callbacks.on_quest_accepted then
        self.callbacks.on_quest_accepted(quest_id)
    end

    return true
end

-- Check if quest objectives are all completed
function quest:isObjectivesCompleted(quest_id)
    local state = self.quest_states[quest_id]
    if not state then return false end

    for i, progress in ipairs(state.objectives) do
        if not progress.completed then
            return false
        end
    end

    return true
end

-- Update quest progress
function quest:updateProgress(quest_id, objective_index, amount)
    local def = self.quest_registry[quest_id]
    local state = self.quest_states[quest_id]

    if not def or not state then return false end
    if state.state ~= self.STATE.ACTIVE then return false end

    local progress = state.objectives[objective_index]
    if not progress or progress.completed then return false end

    -- Update progress
    progress.current = math.min(progress.current + amount, progress.target)

    -- Check if objective completed
    if progress.current >= progress.target then
        progress.completed = true
    end

    -- Check if all objectives completed
    if self:isObjectivesCompleted(quest_id) then
        state.state = self.STATE.COMPLETED

        if self.callbacks.on_quest_completed then
            self.callbacks.on_quest_completed(quest_id)
        end
    end

    -- Trigger progress callback
    if self.callbacks.on_objective_updated then
        self.callbacks.on_objective_updated(quest_id, objective_index, progress.current, progress.target)
    end

    return true
end

-- Helper: Track kill progress
function quest:onEnemyKilled(enemy_type)
    for quest_id, def in pairs(self.quest_registry) do
        local state = self.quest_states[quest_id]
        if state and state.state == self.STATE.ACTIVE then
            for obj_idx, obj in ipairs(def.objectives) do
                if obj.type == self.TYPE.KILL and obj.target == enemy_type then
                    self:updateProgress(quest_id, obj_idx, 1)
                end
            end
        end
    end
end

-- Helper: Track item collection
function quest:onItemCollected(item_type, count)
    count = count or 1
    for quest_id, def in pairs(self.quest_registry) do
        local state = self.quest_states[quest_id]
        if state and state.state == self.STATE.ACTIVE then
            for obj_idx, obj in ipairs(def.objectives) do
                if obj.type == self.TYPE.COLLECT and obj.target == item_type then
                    self:updateProgress(quest_id, obj_idx, count)
                end
            end
        end
    end
end

-- Helper: Track NPC talk
function quest:onNPCTalked(npc_id)
    for quest_id, def in pairs(self.quest_registry) do
        local state = self.quest_states[quest_id]
        if state and state.state == self.STATE.ACTIVE then
            for obj_idx, obj in ipairs(def.objectives) do
                if obj.type == self.TYPE.TALK and obj.target == npc_id then
                    self:updateProgress(quest_id, obj_idx, 1)
                end
            end
        end
    end
end

-- Helper: Track location exploration
function quest:onLocationVisited(location_id)
    for quest_id, def in pairs(self.quest_registry) do
        local state = self.quest_states[quest_id]
        if state and state.state == self.STATE.ACTIVE then
            for obj_idx, obj in ipairs(def.objectives) do
                if obj.type == self.TYPE.EXPLORE and obj.target == location_id then
                    self:updateProgress(quest_id, obj_idx, 1)
                end
            end
        end
    end
end

-- Helper: Track item delivery
function quest:onItemDelivered(item_type, npc_id)
    for quest_id, def in pairs(self.quest_registry) do
        local state = self.quest_states[quest_id]
        if state and state.state == self.STATE.ACTIVE then
            for obj_idx, obj in ipairs(def.objectives) do
                if obj.type == self.TYPE.DELIVER
                   and obj.target == item_type
                   and obj.npc == npc_id then
                    self:updateProgress(quest_id, obj_idx, 1)
                end
            end
        end
    end
end

-- Turn in quest (claim rewards)
function quest:turnIn(quest_id)
    local def = self.quest_registry[quest_id]
    local state = self.quest_states[quest_id]

    if not def or not state then return false, nil end
    if state.state ~= self.STATE.COMPLETED then return false, nil end

    -- Mark as turned in
    state.state = self.STATE.TURNED_IN

    -- Get rewards
    local rewards = def.rewards or {}

    -- Trigger callback
    if self.callbacks.on_quest_turned_in then
        self.callbacks.on_quest_turned_in(quest_id, rewards)
    end

    return true, rewards
end

-- Get quest definition
function quest:getDefinition(quest_id)
    return self.quest_registry[quest_id]
end

-- Get quest state
function quest:getState(quest_id)
    return self.quest_states[quest_id]
end

-- Get all active quests
function quest:getActiveQuests()
    local active = {}
    for quest_id, state in pairs(self.quest_states) do
        if state.state == self.STATE.ACTIVE then
            table.insert(active, {
                id = quest_id,
                def = self.quest_registry[quest_id],
                state = state
            })
        end
    end
    return active
end

-- Get quests by state
function quest:getQuestsByState(quest_state)
    local quests = {}
    for quest_id, state in pairs(self.quest_states) do
        if state.state == quest_state then
            table.insert(quests, {
                id = quest_id,
                def = self.quest_registry[quest_id],
                state = state
            })
        end
    end
    return quests
end

-- Get quests available from NPC
function quest:getQuestsFromNPC(npc_id)
    local available = {}
    local completable = {}

    for quest_id, def in pairs(self.quest_registry) do
        local state = self.quest_states[quest_id]

        -- Available quests
        if def.giver_npc == npc_id and self:canAccept(quest_id) then
            table.insert(available, {
                id = quest_id,
                def = def,
                state = state
            })
        end

        -- Completable quests
        if def.receiver_npc == npc_id
           and state
           and state.state == self.STATE.COMPLETED then
            table.insert(completable, {
                id = quest_id,
                def = def,
                state = state
            })
        end
    end

    return available, completable
end

-- Serialize for save system
function quest:serialize()
    return {
        quest_states = self.quest_states
    }
end

-- Deserialize from save system
function quest:deserialize(data)
    if data and data.quest_states then
        self.quest_states = data.quest_states
    end
end

-- Reset quest state (for testing)
function quest:resetQuest(quest_id)
    local def = self.quest_registry[quest_id]
    if not def then return false end

    self.quest_states[quest_id] = {
        state = self.STATE.AVAILABLE,
        objectives = self:_initObjectives(def.objectives)
    }

    return true
end

-- Reset all quests
function quest:resetAll()
    for quest_id, def in pairs(self.quest_registry) do
        self:resetQuest(quest_id)
    end
end

-- Export quest states for saving
function quest:exportStates()
    local export_data = {}

    for quest_id, state in pairs(self.quest_states) do
        export_data[quest_id] = {
            state = state.state,
            objectives = {}
        }

        -- Copy objective progress
        for obj_idx, progress in ipairs(state.objectives) do
            export_data[quest_id].objectives[obj_idx] = {
                current = progress.current,
                target = progress.target,
                completed = progress.completed
            }
        end
    end

    return export_data
end

-- Import quest states from save data
function quest:importStates(saved_states)
    if not saved_states then return end

    for quest_id, saved_state in pairs(saved_states) do
        local state = self.quest_states[quest_id]

        if state then
            state.state = saved_state.state

            -- Restore objective progress
            for obj_idx, saved_progress in ipairs(saved_state.objectives) do
                if state.objectives[obj_idx] then
                    state.objectives[obj_idx].current = saved_progress.current
                    state.objectives[obj_idx].target = saved_progress.target
                    state.objectives[obj_idx].completed = saved_progress.completed
                end
            end
        end
    end
end

quest:init()

return quest

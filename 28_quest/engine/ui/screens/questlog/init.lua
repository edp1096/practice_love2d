-- engine/ui/screens/questlog/init.lua
-- Quest log UI screen (shows all quests with details)

local questlog = {}

-- Separate module imports
local render_module = require "engine.ui.screens.questlog.render"
local input_module = require "engine.ui.screens.questlog.input"

function questlog:init(quest_system, scene_control)
    self.quest_system = quest_system
    self.scene_control = scene_control

    -- UI state
    self.selected_category = "active"  -- active, available, completed, all
    self.selected_quest_index = 1
    self.scroll_offset = 0

    -- Categories
    self.categories = {
        { id = "active", label = "Active" },
        { id = "available", label = "Available" },
        { id = "completed", label = "Completed" },
        { id = "all", label = "All Quests" }
    }
    self.selected_category_index = 1

    -- Inject dependencies into modules
    render_module:init(self)
    input_module:init(self)
end

function questlog:enter(from)
    self.selected_category_index = 1
    self.selected_category = "active"
    self.selected_quest_index = 1
    self.scroll_offset = 0
end

function questlog:leave()
    -- Cleanup
end

function questlog:update(dt)
    -- Nothing to update
end

function questlog:draw()
    -- Delegate to render module
    render_module:draw()
end

function questlog:keypressed(key)
    input_module:keypressed(key)
end

function questlog:mousepressed(x, y, button)
    input_module:mousepressed(x, y, button)
end

function questlog:mousemoved(x, y, dx, dy)
    input_module:mousemoved(x, y, dx, dy)
end

function questlog:gamepadpressed(joystick, button)
    input_module:gamepadpressed(joystick, button)
end

function questlog:touchpressed(id, x, y, dx, dy, pressure)
    input_module:touchpressed(id, x, y, dx, dy, pressure)
end

function questlog:wheelmoved(x, y)
    input_module:wheelmoved(x, y)
end

-- Helper: Get quests for current category
function questlog:getQuestsForCategory(category)
    if category == "active" then
        return self.quest_system:getQuestsByState(self.quest_system.STATE.ACTIVE)
    elseif category == "available" then
        return self.quest_system:getQuestsByState(self.quest_system.STATE.AVAILABLE)
    elseif category == "completed" then
        local completed = self.quest_system:getQuestsByState(self.quest_system.STATE.COMPLETED)
        local turned_in = self.quest_system:getQuestsByState(self.quest_system.STATE.TURNED_IN)
        -- Combine both
        for i, quest in ipairs(turned_in) do
            table.insert(completed, quest)
        end
        return completed
    elseif category == "all" then
        local all_quests = {}
        for quest_id, def in pairs(self.quest_system.quest_registry) do
            local state = self.quest_system:getState(quest_id)
            table.insert(all_quests, {
                id = quest_id,
                def = def,
                state = state
            })
        end
        return all_quests
    end
    return {}
end

-- Helper: Get selected quest
function questlog:getSelectedQuest()
    local quests = self:getQuestsForCategory(self.selected_category)
    if #quests == 0 then return nil end

    local index = math.max(1, math.min(self.selected_quest_index, #quests))
    return quests[index]
end

return questlog

-- engine/ui/screens/questlog/init.lua
-- Quest log UI screen (shows all quests with details)

local questlog = {}

-- Separate module imports
local render_module = require "engine.ui.screens.questlog.render"
local input_module = require "engine.ui.screens.questlog.input"
local config = require "engine.ui.screens.questlog.config"
local locale = require "engine.core.locale"

function questlog:enter(from, quest_system)
    self.previous_scene = from
    self.quest_system = quest_system

    -- UI state
    self.selected_category = "active"  -- active, available, completed, all
    self.selected_quest_index = 1
    self.scroll_offset = 0

    -- Categories (use locale keys)
    self.categories = {
        { id = "active", label_key = "quest.active" },
        { id = "available", label_key = "quest.available" },
        { id = "completed", label_key = "quest.completed" },
        { id = "all", label_key = "quest.all" }
    }
    self.selected_category_index = 1

    -- Touch swipe state (for mobile scrolling)
    self.touch_state = {
        active = false,
        id = nil,
        start_y = 0,
        last_y = 0,
        velocity = 0
    }

    -- Initialize modules (only once)
    if not render_module.scene then
        render_module:init(self)
        input_module:init(self)
    end
end

function questlog:leave()
    -- Cleanup
end

function questlog:update(dt)
    -- Handle right stick scrolling (gamepad)
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 then
        local joystick = joysticks[1]
        local ry = joystick:getGamepadAxis("righty")
        local threshold = 0.3

        if math.abs(ry) > threshold then
            local quests = self:getQuestsForCategory(self.selected_category)
            if #quests > 0 then
                -- Scroll speed (pixels per second)
                local scroll_speed = config.SCROLL_SPEED
                local scroll_delta = ry * scroll_speed * dt

                -- Calculate max scroll
                local item_height = config.ITEM_HEIGHT
                local padding = config.PADDING
                local list_h = config.LIST_HEIGHT
                local visible_height = list_h - padding * 2
                local total_content_height = #quests * item_height
                local max_scroll = math.max(0, total_content_height - visible_height)

                -- Apply scroll
                self.scroll_offset = self.scroll_offset + scroll_delta
                self.scroll_offset = math.max(0, math.min(self.scroll_offset, max_scroll))
            end
        end
    end
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
    -- Delegate to input module for button clicks
    input_module:touchpressed(id, x, y, dx, dy, pressure)

    -- Initialize touch state for swipe scrolling
    self.touch_state.active = true
    self.touch_state.id = id
    self.touch_state.start_y = y
    self.touch_state.last_y = y
    self.touch_state.velocity = 0
end

function questlog:touchreleased(id, x, y, dx, dy, pressure)
    -- End touch state
    if self.touch_state.id == id then
        self.touch_state.active = false
        self.touch_state.id = nil
    end
end

function questlog:touchmoved(id, x, y, dx, dy, pressure)
    -- Handle swipe scrolling
    if self.touch_state.active and self.touch_state.id == id then
        local delta_y = y - self.touch_state.last_y
        self.touch_state.last_y = y

        local quests = self:getQuestsForCategory(self.selected_category)
        if #quests > 0 then
            -- Calculate max scroll
            local item_height = config.ITEM_HEIGHT
            local padding = config.PADDING
            local list_h = config.LIST_HEIGHT
            local visible_height = list_h - padding * 2
            local total_content_height = #quests * item_height
            local max_scroll = math.max(0, total_content_height - visible_height)

            -- Apply scroll (inverted: swipe down = scroll up)
            self.scroll_offset = self.scroll_offset - delta_y
            self.scroll_offset = math.max(0, math.min(self.scroll_offset, max_scroll))
        end
    end
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

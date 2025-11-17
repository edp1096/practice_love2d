-- engine/systems/hud/quest_tracker.lua
-- Quest tracker HUD (shows active quests on screen)

local text_ui = require "engine.utils.text"
local shapes = require "engine.utils.shapes"
local colors = require "engine.ui.colors"

local quest_tracker = {}

quest_tracker.title_font = love.graphics.newFont(14)
quest_tracker.objective_font = love.graphics.newFont(12)
quest_tracker.small_font = love.graphics.newFont(10)

function quest_tracker:draw(quest_system, screen_w, screen_h, max_quests)
    max_quests = max_quests or 3  -- Show up to 3 quests

    -- Get both active and completed quests
    local active_quests = quest_system:getActiveQuests()
    local completed_quests = quest_system:getQuestsByState(quest_system.STATE.COMPLETED)

    -- Combine: show active quests first, then completed
    local all_quests = {}
    for _, q in ipairs(active_quests) do
        table.insert(all_quests, q)
    end
    for _, q in ipairs(completed_quests) do
        table.insert(all_quests, q)
    end

    if #all_quests == 0 then return end

    -- Position: top-right corner, left of minimap
    local panel_x = screen_w - 450  -- Moved left to avoid minimap overlap
    local panel_y = 10              -- Aligned with minimap top (padding = 10)
    local panel_width = 300
    local line_height = 18
    local padding = 10

    -- Calculate panel height dynamically
    local total_height = padding * 2 + 20  -- Header
    local quest_count = math.min(#all_quests, max_quests)

    for i = 1, quest_count do
        local quest = all_quests[i]
        local def = quest.def
        total_height = total_height + 30  -- Quest title space
        total_height = total_height + (#def.objectives * line_height)  -- Objectives
        if i < quest_count then
            total_height = total_height + 10  -- Spacing between quests
        end
    end

    -- Background panel
    colors:apply(colors.for_hud_quest_bg or {0, 0, 0}, 0.7)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_width, total_height)

    -- Border
    colors:apply(colors.for_hud_quest_border or {0.3, 0.6, 0.9})
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, panel_width, total_height)
    colors:reset()

    -- Header
    local header_y = panel_y + padding
    text_ui:draw("Quests", panel_x + padding, header_y, colors.for_hud_quest_header or {1, 1, 0}, self.title_font)

    -- Draw quests
    local current_y = header_y + 25

    for i = 1, quest_count do
        local quest = all_quests[i]
        local def = quest.def
        local state = quest.state

        -- Quest title
        local title_color = colors.for_hud_quest_title or {0.8, 0.9, 1}
        text_ui:draw(def.title, panel_x + padding, current_y, title_color, self.title_font)
        current_y = current_y + 22

        -- Objectives
        for obj_idx, obj_def in ipairs(def.objectives) do
            local progress = state.objectives[obj_idx]
            local obj_text = string.format("%s (%d/%d)",
                obj_def.description,
                progress.current,
                progress.target
            )

            -- Color: completed = green, in-progress = white
            local obj_color = progress.completed
                and (colors.for_hud_quest_completed or {0.4, 1, 0.4})
                or (colors.for_hud_quest_in_progress or {0.9, 0.9, 0.9})

            -- Checkbox
            local checkbox_x = panel_x + padding + 5
            local checkbox_y = current_y + 5
            local checkbox_size = 8

            if progress.completed then
                -- Filled checkbox
                colors:apply(colors.for_hud_quest_completed or {0.4, 1, 0.4})
                love.graphics.rectangle("fill", checkbox_x, checkbox_y, checkbox_size, checkbox_size)
            else
                -- Empty checkbox
                colors:apply(colors.for_hud_quest_in_progress or {0.9, 0.9, 0.9})
                love.graphics.rectangle("line", checkbox_x, checkbox_y, checkbox_size, checkbox_size)
            end
            colors:reset()

            -- Objective text
            text_ui:draw(obj_text, checkbox_x + checkbox_size + 8, current_y, obj_color, self.objective_font)
            current_y = current_y + line_height
        end

        -- Quest state indicator
        if state.state == quest_system.STATE.COMPLETED then
            local complete_text = "[Ready to turn in]"
            text_ui:draw(complete_text, panel_x + padding, current_y, colors.for_hud_quest_ready or {1, 1, 0}, self.small_font)
            current_y = current_y + 15
        end

        -- Spacing between quests
        if i < quest_count then
            current_y = current_y + 10
        end
    end

    -- "More quests..." indicator
    if #all_quests > max_quests then
        local more_text = string.format("+ %d more quest%s...",
            #all_quests - max_quests,
            (#all_quests - max_quests) > 1 and "s" or "")
        text_ui:draw(more_text, panel_x + padding, current_y, colors.for_hud_quest_more or {0.7, 0.7, 0.7}, self.small_font)
    end

    colors:reset()
    love.graphics.setLineWidth(1)
end

-- Draw quest notification (popup when quest accepted/completed)
function quest_tracker:drawNotification(title, message, timer, screen_w, screen_h)
    if timer <= 0 then return end

    local panel_width = 350
    local panel_height = 80
    local panel_x = (screen_w - panel_width) / 2
    local panel_y = 100

    -- Fade in/out
    local alpha = 1.0
    if timer < 0.3 then
        alpha = timer / 0.3
    elseif timer > 2.7 then
        alpha = (3.0 - timer) / 0.3
    end

    -- Background
    colors:apply(colors.for_hud_notification_bg or {0.1, 0.1, 0.1}, 0.9 * alpha)
    love.graphics.rectangle("fill", panel_x, panel_y, panel_width, panel_height)

    -- Border
    colors:apply(colors.for_hud_notification_border or {1, 0.8, 0}, alpha)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", panel_x, panel_y, panel_width, panel_height)

    -- Title
    local title_color = colors:withAlpha(colors.for_hud_notification_title or {1, 1, 0}, alpha)
    text_ui:draw(title, panel_x + 15, panel_y + 15, title_color, self.title_font)

    -- Message
    local msg_color = colors:withAlpha(colors.for_hud_notification_text or {1, 1, 1}, alpha)
    text_ui:draw(message, panel_x + 15, panel_y + 40, msg_color, self.objective_font)

    colors:reset()
    love.graphics.setLineWidth(1)
end

return quest_tracker

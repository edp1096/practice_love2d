-- engine/ui/screens/questlog/render.lua
-- Quest log rendering

local display = require "engine.core.display"
local text_ui = require "engine.utils.text"
local shapes = require "engine.utils.shapes"
local colors = require "engine.utils.colors"
local config = require "engine.ui.screens.questlog.config"

local render = {}

-- Fonts
render.title_font = love.graphics.newFont(config.FONT_TITLE)
render.category_font = love.graphics.newFont(config.FONT_CATEGORY)
render.quest_title_font = love.graphics.newFont(config.FONT_QUEST_TITLE)
render.text_font = love.graphics.newFont(config.FONT_TEXT)
render.small_font = love.graphics.newFont(config.FONT_SMALL)

function render:init(questlog_scene)
    self.scene = questlog_scene
end

function render:draw()
    local scene = self.scene
    local SCREEN_W, SCREEN_H = display:GetVirtualDimensions()

    -- Check if we're inside a container
    local in_container = scene.previous_scene and scene.previous_scene.current_tab

    -- Only draw background and attach if NOT in container
    if not in_container then
        -- Attach for virtual coordinates
        display:Attach()

        -- Background overlay
        colors:apply(colors.BLACK, 0.7)
        love.graphics.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
        colors:reset()
    end

    -- Main panel (match inventory design)
    local panel_w = config.PANEL_WIDTH
    local panel_h = config.PANEL_HEIGHT
    local panel_x = (SCREEN_W - panel_w) / 2
    local panel_y = in_container and 70 or (SCREEN_H - panel_h) / 2  -- Higher position in container (tab bar at 20, tab height 30, margin 20)

    -- Panel background and border (match inventory style)
    shapes:drawPanel(panel_x, panel_y, panel_w, panel_h, colors.for_inventory_bg, colors.for_inventory_border, 10)

    -- Title
    local title_y = panel_y + 20
    text_ui:draw("Quest Log", panel_x + panel_w / 2 - 60, title_y, colors.for_ui_title or {1, 1, 1}, self.title_font)

    -- Close button (only if NOT in container)
    if not in_container then
        local close_btn_size = 30
        local close_btn_x = panel_x + panel_w - close_btn_size - 10
        local close_btn_y = panel_y + 10
        local is_close_hovered = false  -- TODO: Add hover detection if needed
        shapes:drawCloseButton(close_btn_x, close_btn_y, close_btn_size, is_close_hovered)
    end

    -- Category tabs
    local tab_y = panel_y + 60
    self:drawCategoryTabs(panel_x, tab_y, panel_w)

    -- Quest list (left side)
    local list_x = panel_x + 20
    local list_y = tab_y + 50
    local list_w = config.LIST_WIDTH
    local list_h = config.LIST_HEIGHT
    self:drawQuestList(list_x, list_y, list_w, list_h)

    -- Quest details (right side)
    local details_x = list_x + list_w + 20
    local details_y = list_y
    local details_w = panel_w - list_w - 60
    local details_h = list_h
    self:drawQuestDetails(details_x, details_y, details_w, details_h)

    -- Help text (only if NOT in container - container shows its own hints)
    if not in_container then
        local help_y = panel_y + panel_h - 30
        local help_text = "ESC: Close  |  Arrow Keys: Navigate  |  Enter: Select"
        text_ui:draw(help_text, panel_x + 20, help_y, colors.for_ui_hint or {0.7, 0.7, 0.7}, self.small_font)

        display:Detach()
    end
end

function render:drawCategoryTabs(panel_x, tab_y, panel_w)
    local scene = self.scene
    local tab_width = config.TAB_WIDTH
    local tab_height = config.TAB_HEIGHT
    local spacing = config.TAB_SPACING
    local start_x = panel_x + 20

    for i, category in ipairs(scene.categories) do
        local tab_x = start_x + (i - 1) * (tab_width + spacing)
        local is_selected = (i == scene.selected_category_index)

        -- Tab background
        if is_selected then
            colors:apply(colors.for_ui_tab_selected or {0.3, 0.6, 0.9})
        else
            colors:apply(colors.for_ui_tab_bg or {0.2, 0.2, 0.2})
        end
        love.graphics.rectangle("fill", tab_x, tab_y, tab_width, tab_height)

        -- Tab border
        colors:apply(colors.for_ui_tab_border or {0.5, 0.5, 0.5})
        love.graphics.rectangle("line", tab_x, tab_y, tab_width, tab_height)

        -- Tab text
        local text_color = is_selected
            and (colors.WHITE or {1, 1, 1})
            or (colors.for_ui_tab_text or {0.8, 0.8, 0.8})

        local text_w = self.category_font:getWidth(category.label)
        text_ui:draw(category.label, tab_x + (tab_width - text_w) / 2, tab_y + 8, text_color, self.category_font)
    end

    colors:reset()
end

function render:drawQuestList(list_x, list_y, list_w, list_h)
    local scene = self.scene
    local quests = scene:getQuestsForCategory(scene.selected_category)

    -- List background
    colors:apply(colors.for_ui_list_bg or {0.15, 0.15, 0.15})
    love.graphics.rectangle("fill", list_x, list_y, list_w, list_h)

    colors:apply(colors.for_ui_list_border or {0.4, 0.4, 0.4})
    love.graphics.rectangle("line", list_x, list_y, list_w, list_h)
    colors:reset()

    if #quests == 0 then
        local no_quest_text = "No quests"
        text_ui:draw(no_quest_text, list_x + 10, list_y + 10, colors.for_ui_hint or {0.6, 0.6, 0.6}, self.text_font)
        return
    end

    -- Enable scissor to clip items outside visible area
    -- Convert virtual coordinates to physical (screen) coordinates for scissor
    local coords = require "engine.core.coords"
    local phys_x, phys_y = coords:virtualToPhysical(list_x, list_y, display)
    local phys_x2, phys_y2 = coords:virtualToPhysical(list_x + list_w, list_y + list_h, display)
    local phys_w = phys_x2 - phys_x
    local phys_h = phys_y2 - phys_y
    love.graphics.setScissor(phys_x, phys_y, phys_w, phys_h)

    -- Draw quest items
    local item_height = config.ITEM_HEIGHT
    local padding = config.PADDING
    local current_y = list_y + padding - scene.scroll_offset

    for i, quest in ipairs(quests) do
        local def = quest.def
        local state = quest.state
        local is_selected = (i == scene.selected_quest_index)

        local item_x = list_x + padding
        local item_y = current_y
        local item_w = list_w - padding * 2
        local item_h = item_height

        -- Selection highlight
        if is_selected then
            colors:apply(colors.for_ui_selection or {0.2, 0.4, 0.7}, 0.5)
            love.graphics.rectangle("fill", item_x, item_y, item_w, item_h)
        end

        -- Quest title
        local title_color = is_selected
            and (colors.for_ui_selection_text or {1, 1, 1})
            or (colors.for_ui_text or {0.9, 0.9, 0.9})

        text_ui:draw(def.title, item_x + 5, item_y + 5, title_color, self.quest_title_font)

        -- Quest state indicator
        local state_text = ""
        local state_color = {0.7, 0.7, 0.7}

        if state.state == scene.quest_system.STATE.ACTIVE then
            state_text = "In Progress"
            state_color = colors.for_quest_in_progress or {0.8, 0.8, 1}
        elseif state.state == scene.quest_system.STATE.COMPLETED then
            state_text = "Ready to turn in"
            state_color = colors.for_quest_ready or {1, 1, 0}
        elseif state.state == scene.quest_system.STATE.TURNED_IN then
            state_text = "Completed"
            state_color = colors.for_quest_completed or {0.4, 1, 0.4}
        elseif state.state == scene.quest_system.STATE.AVAILABLE then
            state_text = "Available"
            state_color = colors.for_quest_available or {0.9, 0.9, 0.9}
        end

        text_ui:draw(state_text, item_x + 5, item_y + 28, state_color, self.small_font)

        -- Divider
        colors:apply(colors.for_ui_divider or {0.3, 0.3, 0.3})
        love.graphics.line(item_x, item_y + item_h, item_x + item_w, item_y + item_h)

        current_y = current_y + item_h
        colors:reset()
    end

    -- Disable scissor
    love.graphics.setScissor()

    -- Draw scrollbar if needed
    local total_content_height = #quests * item_height
    local visible_height = list_h - padding * 2

    if total_content_height > visible_height then
        local scrollbar_x = list_x + list_w - 8
        local scrollbar_w = 6
        local scrollbar_track_h = list_h - 10
        local scrollbar_y = list_y + 5

        -- Scrollbar track
        colors:apply({0.2, 0.2, 0.2}, 0.5)
        love.graphics.rectangle("fill", scrollbar_x, scrollbar_y, scrollbar_w, scrollbar_track_h)

        -- Scrollbar thumb
        local thumb_height = math.max(20, (visible_height / total_content_height) * scrollbar_track_h)
        local max_scroll = total_content_height - visible_height
        local thumb_y = scrollbar_y + (scene.scroll_offset / max_scroll) * (scrollbar_track_h - thumb_height)

        colors:apply({0.5, 0.5, 0.5}, 0.8)
        love.graphics.rectangle("fill", scrollbar_x, thumb_y, scrollbar_w, thumb_height, 3, 3)
        colors:reset()
    end
end

function render:drawQuestDetails(details_x, details_y, details_w, details_h)
    local scene = self.scene
    local quest = scene:getSelectedQuest()

    -- Details background
    colors:apply(colors.for_ui_details_bg or {0.12, 0.12, 0.12})
    love.graphics.rectangle("fill", details_x, details_y, details_w, details_h)

    colors:apply(colors.for_ui_details_border or {0.4, 0.4, 0.4})
    love.graphics.rectangle("line", details_x, details_y, details_w, details_h)
    colors:reset()

    if not quest then
        text_ui:draw("Select a quest to view details", details_x + 10, details_y + 10, colors.for_ui_hint or {0.6, 0.6, 0.6}, self.text_font)
        return
    end

    local def = quest.def
    local state = quest.state
    local current_y = details_y + 15
    local padding = 15

    -- Quest title
    text_ui:draw(def.title, details_x + padding, current_y, colors.for_ui_title or {1, 1, 1}, self.quest_title_font)
    current_y = current_y + 30

    -- Description
    colors:apply(colors.for_ui_divider or {0.5, 0.5, 0.5})
    love.graphics.line(details_x + padding, current_y, details_x + details_w - padding, current_y)
    current_y = current_y + 10

    text_ui:draw("Description:", details_x + padding, current_y, colors.for_ui_label or {0.7, 0.9, 1}, self.text_font)
    current_y = current_y + 20

    -- Wrap description text
    local wrapped_desc = self:wrapText(def.description, details_w - padding * 2, self.text_font)
    for i, line in ipairs(wrapped_desc) do
        text_ui:draw(line, details_x + padding, current_y, colors.for_ui_text or {0.9, 0.9, 0.9}, self.text_font)
        current_y = current_y + 18
    end

    current_y = current_y + 10

    -- Objectives
    colors:apply(colors.for_ui_divider or {0.5, 0.5, 0.5})
    love.graphics.line(details_x + padding, current_y, details_x + details_w - padding, current_y)
    current_y = current_y + 10

    text_ui:draw("Objectives:", details_x + padding, current_y, colors.for_ui_label or {0.7, 0.9, 1}, self.text_font)
    current_y = current_y + 22

    for obj_idx, obj_def in ipairs(def.objectives) do
        local progress = state.objectives[obj_idx]
        local obj_text = string.format("  %s (%d/%d)",
            obj_def.description,
            progress.current,
            progress.target
        )

        local obj_color = progress.completed
            and (colors.for_quest_completed or {0.4, 1, 0.4})
            or (colors.for_ui_text or {0.9, 0.9, 0.9})

        -- Checkbox
        local checkbox_x = details_x + padding + 8
        local checkbox_y = current_y + 4
        local checkbox_size = 10

        if progress.completed then
            colors:apply(colors.for_quest_completed or {0.4, 1, 0.4})
            love.graphics.rectangle("fill", checkbox_x, checkbox_y, checkbox_size, checkbox_size)
        else
            colors:apply(colors.for_ui_text or {0.9, 0.9, 0.9})
            love.graphics.rectangle("line", checkbox_x, checkbox_y, checkbox_size, checkbox_size)
        end
        colors:reset()

        text_ui:draw(obj_text, checkbox_x + checkbox_size + 8, current_y, obj_color, self.text_font)
        current_y = current_y + 20
    end

    current_y = current_y + 10

    -- Rewards
    if def.rewards and (def.rewards.gold or def.rewards.exp or #(def.rewards.items or {}) > 0) then
        colors:apply(colors.for_ui_divider or {0.5, 0.5, 0.5})
        love.graphics.line(details_x + padding, current_y, details_x + details_w - padding, current_y)
        current_y = current_y + 10

        text_ui:draw("Rewards:", details_x + padding, current_y, colors.for_ui_label or {0.7, 0.9, 1}, self.text_font)
        current_y = current_y + 20

        if def.rewards.gold then
            text_ui:draw("  Gold: " .. def.rewards.gold, details_x + padding, current_y, colors.for_reward_gold or {1, 0.8, 0}, self.text_font)
            current_y = current_y + 18
        end

        if def.rewards.exp then
            text_ui:draw("  EXP: " .. def.rewards.exp, details_x + padding, current_y, colors.for_reward_exp or {0.5, 1, 0.5}, self.text_font)
            current_y = current_y + 18
        end

        if def.rewards.items and #def.rewards.items > 0 then
            local items_text = "  Items: " .. table.concat(def.rewards.items, ", ")
            text_ui:draw(items_text, details_x + padding, current_y, colors.for_reward_items or {0.7, 0.7, 1}, self.text_font)
            current_y = current_y + 18
        end
    end
end

-- Helper: Wrap text to fit width
function render:wrapText(text, max_width, font)
    local words = {}
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end

    local lines = {}
    local current_line = ""

    for i, word in ipairs(words) do
        local test_line = current_line == "" and word or (current_line .. " " .. word)
        local test_width = font:getWidth(test_line)

        if test_width <= max_width then
            current_line = test_line
        else
            if current_line ~= "" then
                table.insert(lines, current_line)
            end
            current_line = word
        end
    end

    if current_line ~= "" then
        table.insert(lines, current_line)
    end

    return lines
end

return render

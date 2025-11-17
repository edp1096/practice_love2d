-- engine/ui/screens/questlog/input.lua
-- Quest log input handling

local scene_control = require "engine.core.scene_control"
local display = require "engine.core.display"
local coords = require "engine.core.coords"
local input_sys = require "engine.core.input"

local input = {}

function input:init(questlog_scene)
    self.scene = questlog_scene
    self.hover_close = false
end

-- Helper: Auto-scroll to keep selected item visible
function input:updateScrollToSelection()
    local scene = self.scene
    local quests = scene:getQuestsForCategory(scene.selected_category)
    if #quests == 0 then return end

    local item_height = 50
    local padding = 5
    local list_h = 310  -- panel_h (450) - 140 (from render.lua:77)
    local visible_height = list_h - padding * 2

    -- Calculate selected item position
    local selected_y = (scene.selected_quest_index - 1) * item_height
    local selected_bottom = selected_y + item_height

    -- Adjust scroll to keep selection visible
    if selected_y < scene.scroll_offset then
        -- Item is above visible area, scroll up
        scene.scroll_offset = selected_y
    elseif selected_bottom > scene.scroll_offset + visible_height then
        -- Item is below visible area, scroll down
        scene.scroll_offset = selected_bottom - visible_height
    end

    -- Clamp scroll to valid range
    local total_content_height = #quests * item_height
    local max_scroll = math.max(0, total_content_height - visible_height)
    scene.scroll_offset = math.max(0, math.min(scene.scroll_offset, max_scroll))
end

function input:keypressed(key)
    local scene = self.scene

    -- J key to toggle questlog (same as I key for inventory)
    if input_sys:wasPressed("open_questlog", "keyboard", key) then
        scene_control.pop()
        return
    end

    if key == "escape" or key == "q" then
        scene_control.pop()
        return
    end

    -- Category navigation (left/right or tab/shift+tab)
    if key == "left" or (key == "tab" and love.keyboard.isDown("lshift", "rshift")) then
        scene.selected_category_index = scene.selected_category_index - 1
        if scene.selected_category_index < 1 then
            scene.selected_category_index = #scene.categories
        end
        scene.selected_category = scene.categories[scene.selected_category_index].id
        scene.selected_quest_index = 1
        scene.scroll_offset = 0  -- Reset scroll when changing category
        return
    end

    if key == "right" or key == "tab" then
        scene.selected_category_index = scene.selected_category_index + 1
        if scene.selected_category_index > #scene.categories then
            scene.selected_category_index = 1
        end
        scene.selected_category = scene.categories[scene.selected_category_index].id
        scene.selected_quest_index = 1
        scene.scroll_offset = 0  -- Reset scroll when changing category
        return
    end

    -- Quest navigation (up/down)
    if key == "up" then
        scene.selected_quest_index = scene.selected_quest_index - 1
        if scene.selected_quest_index < 1 then
            local quests = scene:getQuestsForCategory(scene.selected_category)
            scene.selected_quest_index = math.max(1, #quests)
        end
        self:updateScrollToSelection()
        return
    end

    if key == "down" then
        local quests = scene:getQuestsForCategory(scene.selected_category)
        scene.selected_quest_index = scene.selected_quest_index + 1
        if scene.selected_quest_index > #quests then
            scene.selected_quest_index = 1
        end
        self:updateScrollToSelection()
        return
    end
end

function input:mousepressed(x, y, button)
    if button ~= 1 then return end

    local scene = self.scene
    local SCREEN_W, SCREEN_H = display:GetVirtualDimensions()

    -- Convert to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Check if we're inside a container
    local in_container = scene.previous_scene and scene.previous_scene.current_tab

    -- Panel dimensions (match render.lua)
    local panel_w = 720  -- Match inventory width
    local panel_h = 450  -- Reduced from 500
    local panel_x = (SCREEN_W - panel_w) / 2
    local panel_y = in_container and 70 or (SCREEN_H - panel_h) / 2

    -- Close button (only if NOT in container)
    if not in_container then
        local close_x = panel_x + panel_w - 40
        local close_y = panel_y + 10
        local close_size = 30

        if vx >= close_x and vx <= close_x + close_size
           and vy >= close_y and vy <= close_y + close_size then
            scene_control.pop()
            return
        end
    end

    -- Category tabs (match render.lua)
    local tab_y = panel_y + 60
    local tab_width = 130  -- Reduced from 150
    local tab_height = 28  -- Reduced from 35
    local spacing = 8  -- Reduced from 10
    local start_x = panel_x + 20

    for i, category in ipairs(scene.categories) do
        local tab_x = start_x + (i - 1) * (tab_width + spacing)

        if vx >= tab_x and vx <= tab_x + tab_width
           and vy >= tab_y and vy <= tab_y + tab_height then
            scene.selected_category_index = i
            scene.selected_category = category.id
            scene.selected_quest_index = 1
            scene.scroll_offset = 0  -- Reset scroll when changing category
            return
        end
    end

    -- Quest list (match render.lua)
    local list_x = panel_x + 20
    local list_y = tab_y + 50
    local list_w = 320
    local list_h = panel_h - 140

    if vx >= list_x and vx <= list_x + list_w
       and vy >= list_y and vy <= list_y + list_h then
        local quests = scene:getQuestsForCategory(scene.selected_category)
        local item_height = 50
        local padding = 5

        -- Account for scroll offset when calculating clicked item
        local relative_y = vy - (list_y + padding) + scene.scroll_offset
        local clicked_index = math.floor(relative_y / item_height) + 1

        if clicked_index >= 1 and clicked_index <= #quests then
            scene.selected_quest_index = clicked_index
            self:updateScrollToSelection()
        end
        return
    end
end

function input:mousemoved(x, y, dx, dy)
    local SCREEN_W, SCREEN_H = display:GetVirtualDimensions()

    -- Convert to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Check if we're inside a container
    local scene = self.scene
    local in_container = scene.previous_scene and scene.previous_scene.current_tab

    -- Panel dimensions (match render.lua)
    local panel_w = 720  -- Match inventory width
    local panel_h = 450  -- Reduced from 500
    local panel_x = (SCREEN_W - panel_w) / 2
    local panel_y = in_container and 70 or (SCREEN_H - panel_h) / 2

    -- Close button hover (only if NOT in container)
    if not in_container then
        local close_x = panel_x + panel_w - 40
        local close_y = panel_y + 10
        local close_size = 30

        self.hover_close = (vx >= close_x and vx <= close_x + close_size
                           and vy >= close_y and vy <= close_y + close_size)
    else
        self.hover_close = false
    end
end

function input:gamepadpressed(joystick, button)
    local scene = self.scene

    -- Toggle questlog with same button (Back button)
    if input_sys:wasPressed("open_questlog", "gamepad", button) then
        scene_control.pop()
        return
    end

    -- Cancel/pause actions
    if input_sys:wasPressed("cancel", "gamepad", button) or
       input_sys:wasPressed("pause", "gamepad", button) then
        scene_control.pop()
        return
    end

    -- Navigation using input system
    if input_sys:wasPressed("move_left", "gamepad", button) then
        self:keypressed("left")
        return
    end

    if input_sys:wasPressed("move_right", "gamepad", button) then
        self:keypressed("right")
        return
    end

    if input_sys:wasPressed("move_up", "gamepad", button) then
        self:keypressed("up")
        return
    end

    if input_sys:wasPressed("move_down", "gamepad", button) then
        self:keypressed("down")
        return
    end
end

function input:touchpressed(id, x, y, dx, dy, pressure)
    -- Treat touch as mouse click
    self:mousepressed(x, y, 1)
end

function input:wheelmoved(x, y)
    local scene = self.scene
    local quests = scene:getQuestsForCategory(scene.selected_category)
    if #quests == 0 then return end

    -- Scroll amount per wheel tick (in pixels)
    local scroll_amount = 50  -- One quest item height

    local item_height = 50
    local padding = 5
    local list_h = 310  -- panel_h (450) - 140
    local visible_height = list_h - padding * 2
    local total_content_height = #quests * item_height
    local max_scroll = math.max(0, total_content_height - visible_height)

    if y > 0 then
        -- Scroll up
        scene.scroll_offset = scene.scroll_offset - scroll_amount
    elseif y < 0 then
        -- Scroll down
        scene.scroll_offset = scene.scroll_offset + scroll_amount
    end

    -- Clamp scroll to valid range
    scene.scroll_offset = math.max(0, math.min(scene.scroll_offset, max_scroll))
end

return input

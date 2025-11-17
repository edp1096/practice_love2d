-- engine/ui/screens/questlog/input.lua
-- Quest log input handling

local display = require "engine.core.display"
local coords = require "engine.core.coords"

local input = {}

function input:init(questlog_scene)
    self.scene = questlog_scene
    self.hover_close = false
end

function input:keypressed(key)
    local scene = self.scene

    if key == "escape" or key == "q" then
        scene.scene_control:pop()
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
        return
    end

    if key == "right" or key == "tab" then
        scene.selected_category_index = scene.selected_category_index + 1
        if scene.selected_category_index > #scene.categories then
            scene.selected_category_index = 1
        end
        scene.selected_category = scene.categories[scene.selected_category_index].id
        scene.selected_quest_index = 1
        return
    end

    -- Quest navigation (up/down)
    if key == "up" then
        scene.selected_quest_index = scene.selected_quest_index - 1
        if scene.selected_quest_index < 1 then
            local quests = scene:getQuestsForCategory(scene.selected_category)
            scene.selected_quest_index = math.max(1, #quests)
        end
        return
    end

    if key == "down" then
        local quests = scene:getQuestsForCategory(scene.selected_category)
        scene.selected_quest_index = scene.selected_quest_index + 1
        if scene.selected_quest_index > #quests then
            scene.selected_quest_index = 1
        end
        return
    end
end

function input:mousepressed(x, y, button)
    if button ~= 1 then return end

    local scene = self.scene
    local SCREEN_W, SCREEN_H = display:GetVirtualDimensions()

    -- Convert to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Panel dimensions
    local panel_w = 800
    local panel_h = 500
    local panel_x = (SCREEN_W - panel_w) / 2
    local panel_y = (SCREEN_H - panel_h) / 2

    -- Close button
    local close_x = panel_x + panel_w - 40
    local close_y = panel_y + 10
    local close_size = 30

    if vx >= close_x and vx <= close_x + close_size
       and vy >= close_y and vy <= close_y + close_size then
        scene.scene_control:pop()
        return
    end

    -- Category tabs
    local tab_y = panel_y + 60
    local tab_width = 150
    local tab_height = 35
    local spacing = 10
    local start_x = panel_x + 20

    for i, category in ipairs(scene.categories) do
        local tab_x = start_x + (i - 1) * (tab_width + spacing)

        if vx >= tab_x and vx <= tab_x + tab_width
           and vy >= tab_y and vy <= tab_y + tab_height then
            scene.selected_category_index = i
            scene.selected_category = category.id
            scene.selected_quest_index = 1
            return
        end
    end

    -- Quest list
    local list_x = panel_x + 20
    local list_y = tab_y + 50
    local list_w = 320
    local list_h = panel_h - 140

    if vx >= list_x and vx <= list_x + list_w
       and vy >= list_y and vy <= list_y + list_h then
        local quests = scene:getQuestsForCategory(scene.selected_category)
        local item_height = 50
        local padding = 5

        local relative_y = vy - (list_y + padding)
        local clicked_index = math.floor(relative_y / item_height) + 1

        if clicked_index >= 1 and clicked_index <= #quests then
            scene.selected_quest_index = clicked_index
        end
        return
    end
end

function input:mousemoved(x, y, dx, dy)
    local SCREEN_W, SCREEN_H = display:GetVirtualDimensions()

    -- Convert to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Panel dimensions
    local panel_w = 800
    local panel_h = 500
    local panel_x = (SCREEN_W - panel_w) / 2
    local panel_y = (SCREEN_H - panel_h) / 2

    -- Close button hover
    local close_x = panel_x + panel_w - 40
    local close_y = panel_y + 10
    local close_size = 30

    self.hover_close = (vx >= close_x and vx <= close_x + close_size
                       and vy >= close_y and vy <= close_y + close_size)
end

function input:gamepadpressed(joystick, button)
    local scene = self.scene
    local input_config = require "game.data.input_config"

    -- Map gamepad buttons
    local action = input_config:getGamepadAction(button)

    if action == "cancel" or action == "pause" then
        scene.scene_control:pop()
        return
    end

    if action == "move_left" then
        self:keypressed("left")
        return
    end

    if action == "move_right" then
        self:keypressed("right")
        return
    end

    if action == "move_up" then
        self:keypressed("up")
        return
    end

    if action == "move_down" then
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

    if y > 0 then
        -- Scroll up
        scene.selected_quest_index = scene.selected_quest_index - 1
        if scene.selected_quest_index < 1 then
            local quests = scene:getQuestsForCategory(scene.selected_category)
            scene.selected_quest_index = math.max(1, #quests)
        end
    elseif y < 0 then
        -- Scroll down
        local quests = scene:getQuestsForCategory(scene.selected_category)
        scene.selected_quest_index = scene.selected_quest_index + 1
        if scene.selected_quest_index > #quests then
            scene.selected_quest_index = 1
        end
    end
end

return input

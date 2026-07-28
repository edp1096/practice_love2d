-- engine/ui/screens/load/slot_renderer.lua
-- Slot rendering logic for load scene

local slot_renderer = {}
local shapes = require "engine.utils.shapes"
local text_ui = require "engine.utils.text"
local colors = require "engine.utils.colors"
local locale = require "engine.core.locale"

-- Render individual save slot
function slot_renderer.drawSlot(load_scene, slot, i, is_selected)
    local y = load_scene.layout.slots_start_y + (i - 1) * load_scene.layout.slot_spacing

    -- Slot background and border
    local state = is_selected and "selected" or "normal"
    shapes:drawButton(load_scene.virtual_width * 0.15, y - 5, load_scene.virtual_width * 0.7, 80, state, 0)

    if slot.slot == "back" then
        slot_renderer.drawBackButton(load_scene, slot, y, is_selected)
    elseif slot.exists then
        slot_renderer.drawExistingSlot(load_scene, slot, i, y, is_selected)
    else
        slot_renderer.drawEmptySlot(load_scene, slot, y)
    end
end

-- Render "Back to Menu" button
function slot_renderer.drawBackButton(load_scene, slot, y, is_selected)
    love.graphics.setFont(load_scene.slotFont)
    colors:apply(is_selected and colors.for_menu_selected or colors.for_text_light)
    love.graphics.printf(slot.display_name, 0, y + 25, load_scene.virtual_width, "center")
end

-- Render existing save slot with data
function slot_renderer.drawExistingSlot(load_scene, slot, i, y, is_selected)
    -- Slot title
    local title_color = is_selected and colors.for_menu_selected or colors.for_text_normal
    text_ui:draw(locale:t("save.slot", {num = slot.slot}), load_scene.virtual_width * 0.2, y, title_color, load_scene.slotFont)

    -- HP info
    text_ui:draw(locale:t("hud.hp") .. ": " .. slot.hp .. "/" .. slot.max_hp, load_scene.virtual_width * 0.2, y + 28, colors.for_text_gray, load_scene.infoFont)
    text_ui:draw(slot.map_display or locale:t("save.unknown"), load_scene.virtual_width * 0.2, y + 48, colors.for_text_gray, load_scene.infoFont)

    -- Timestamp
    text_ui:draw(slot.time_string, load_scene.virtual_width * 0.2, y + 65, colors.for_text_dark_gray, load_scene.hintFont)

    -- Draw X delete button
    slot_renderer.drawDeleteButton(load_scene, i, y)
end

-- Render empty save slot
function slot_renderer.drawEmptySlot(load_scene, slot, y)
    text_ui:draw(locale:t("save.slot", {num = slot.slot}) .. " - " .. locale:t("save.empty"), load_scene.virtual_width * 0.2, y + 25, colors.for_text_dim, load_scene.slotFont)
end

-- Render delete button (X button)
function slot_renderer.drawDeleteButton(load_scene, i, y)
    local delete_x = load_scene.virtual_width * 0.15 + load_scene.virtual_width * 0.7 - 40
    local delete_y = y + 5
    local delete_size = 30
    local is_delete_hovered = (load_scene.mouse_over_delete == i)

    shapes:drawCloseButton(delete_x, delete_y, delete_size, is_delete_hovered)
end

-- Render all slots
function slot_renderer.drawAllSlots(load_scene)
    for i, slot in ipairs(load_scene.slots) do
        local is_selected = (i == load_scene.selected)
        slot_renderer.drawSlot(load_scene, slot, i, is_selected)
    end
end

-- Render delete confirmation dialog
function slot_renderer.drawConfirmDialog(load_scene)
    -- Dark overlay
    shapes:drawOverlay(load_scene.virtual_width, load_scene.virtual_height, 0.85)

    -- Confirmation text
    love.graphics.setFont(load_scene.confirmFont)
    colors:apply(colors.for_button_delete_border_selected)
    local confirm_text = locale:t("save.confirm_delete_slot", {num = load_scene.delete_slot})
    love.graphics.printf(confirm_text, 0, load_scene.virtual_height / 2 - 60, load_scene.virtual_width, "center")

    love.graphics.setFont(load_scene.hintFont)
    colors:apply(colors.for_text_light)
    love.graphics.printf(locale:t("save.cannot_undo"), 0, load_scene.virtual_height / 2 - 20, load_scene.virtual_width, "center")

    -- Draw Yes/No buttons
    slot_renderer.drawConfirmButtons(load_scene)

    -- Hint text
    slot_renderer.drawConfirmHints(load_scene)
end

-- Render Yes/No buttons for confirmation dialog
function slot_renderer.drawConfirmButtons(load_scene)
    local button_y = load_scene.virtual_height / 2 + 60
    local button_width = 120
    local button_height = 50
    local button_spacing = 40

    -- No button (left)
    local no_x = load_scene.virtual_width / 2 - button_width - button_spacing / 2
    local is_no_selected = (load_scene.confirm_selected == 1)

    local no_state = is_no_selected and "selected" or "normal"
    shapes:drawButton(no_x, button_y, button_width, button_height, no_state, 0)

    love.graphics.setFont(load_scene.slotFont)
    colors:apply(is_no_selected and colors.for_text_normal or colors.for_text_light)
    love.graphics.printf(locale:t("save.no"), no_x, button_y + 12, button_width, "center")

    -- Yes button (right)
    local yes_x = load_scene.virtual_width / 2 + button_spacing / 2
    local is_yes_selected = (load_scene.confirm_selected == 2)

    -- Custom red color for Yes button
    colors:apply(is_yes_selected and colors.for_button_delete_selected or colors.for_button_delete_normal)
    love.graphics.rectangle("fill", yes_x, button_y, button_width, button_height)

    colors:apply(is_yes_selected and colors.for_button_delete_border_selected or colors.for_button_delete_border_normal)
    love.graphics.rectangle("line", yes_x, button_y, button_width, button_height)

    love.graphics.setFont(load_scene.slotFont)
    colors:apply(is_yes_selected and colors.for_text_normal or colors:withAlpha(colors.for_text_light, 0.9))
    love.graphics.printf(locale:t("save.yes"), yes_x, button_y + 12, button_width, "center")
end

-- Render confirmation dialog hints
function slot_renderer.drawConfirmHints(load_scene)
    local button_y = load_scene.virtual_height / 2 + 60
    local button_height = 50

    love.graphics.setFont(load_scene.hintFont)
    colors:apply(colors.for_text_mid_gray)

    local input = require "engine.core.input"
    if input:hasGamepad() then
        love.graphics.printf(input:getPrompt("menu_left") .. input:getPrompt("menu_right") .. ": Select | " .. input:getPrompt("menu_select") .. ": Confirm | " .. input:getPrompt("menu_back") .. ": Cancel",
            0, button_y + button_height + 30, load_scene.virtual_width, "center")
        love.graphics.printf("Or use keyboard/mouse",
            0, button_y + button_height + 50, load_scene.virtual_width, "center")
    else
        love.graphics.printf("Arrow Keys / WASD to select | Enter to confirm | ESC to cancel",
            0, button_y + button_height + 30, load_scene.virtual_width, "center")
        love.graphics.printf("Or click a button with mouse",
            0, button_y + button_height + 50, load_scene.virtual_width, "center")
    end
end

-- Render input hints at bottom
function slot_renderer.drawInputHints(load_scene)
    love.graphics.setFont(load_scene.hintFont)
    colors:apply(colors.for_text_dim)

    local input = require "engine.core.input"
    if input:hasGamepad() then
        love.graphics.printf("D-Pad: Navigate | " .. input:getPrompt("menu_select") .. ": Load | " .. input:getPrompt("interact") .. ": Delete | " .. input:getPrompt("menu_back") .. ": Back",
            0, load_scene.layout.hint_y - 20, load_scene.virtual_width, "center")
        love.graphics.printf("Keyboard: Arrow/WASD | Enter: Load | Delete: Delete | ESC: Back | Mouse: Hover & Click [X]",
            0, load_scene.layout.hint_y, load_scene.virtual_width, "center")
    else
        love.graphics.printf("Arrow Keys / WASD: Navigate | Enter: Select | Delete: Delete | ESC: Back",
            0, load_scene.layout.hint_y - 20, load_scene.virtual_width, "center")
        love.graphics.printf("Mouse: Hover and Click | Click [X] button to delete",
            0, load_scene.layout.hint_y, load_scene.virtual_width, "center")
    end
end

return slot_renderer

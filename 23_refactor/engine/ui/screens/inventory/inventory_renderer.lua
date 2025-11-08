-- engine/ui/screens/inventory/slot_renderer.lua
-- Renders inventory slots, items, and UI elements

local slot_renderer = {}
local shapes = require "engine.ui.shapes"
local text_ui = require "engine.utils.text"

-- Render the close button in the top-right corner
function slot_renderer.renderCloseButton(window_x, window_y, window_w, close_button_size, close_button_padding)
    local close_x = window_x + window_w - close_button_size - close_button_padding
    local close_y = window_y + close_button_padding

    shapes:drawCloseButton(close_x, close_y, close_button_size, false)

    return { x = close_x, y = close_y, size = close_button_size }
end

-- Render the item grid with slots
function slot_renderer.renderItemGrid(inventory, selected_slot, slot_size, slot_spacing, title_font, item_font, desc_font)
    local display = require "engine.core.display"
    local vw, vh = display:GetVirtualDimensions()

    if #inventory.items == 0 then
        local empty_text = "No items in inventory"
        local empty_w = item_font:getWidth(empty_text)
        text_ui:draw(empty_text, (vw - empty_w) / 2, vh / 2, {0.5, 0.5, 0.5, 1}, item_font)
        return
    end

    local start_x = (vw - (slot_size + slot_spacing) * math.min(#inventory.items, 5)) / 2
    local start_y = 150

    for i, item in ipairs(inventory.items) do
        local row = math.floor((i - 1) / 5)
        local col = (i - 1) % 5
        local x = start_x + col * (slot_size + slot_spacing)
        local y = start_y + row * (slot_size + slot_spacing)

        -- Draw slot background and border
        shapes:drawSlot(x, y, slot_size, i == selected_slot, false, 5)

        -- Draw item icon (colored HP text)
        local icon_text = "HP"
        local icon_color
        if item.type == "small_potion" then
            icon_color = {0.5, 1, 0.5, 1}
        elseif item.type == "large_potion" then
            icon_color = {0.3, 1, 0.8, 1}
        else
            icon_color = {1, 1, 1, 1}
        end
        local icon_w = title_font:getWidth(icon_text)
        text_ui:draw(icon_text, x + (slot_size - icon_w) / 2, y + 15, icon_color, title_font)

        -- Draw quantity
        text_ui:draw("x" .. item.quantity, x + 8, y + slot_size - 25, {1, 1, 1, 1}, item_font)

        -- Draw slot number
        text_ui:draw(tostring(i), x + 5, y + 5, {0.7, 0.7, 0.7, 1}, desc_font)
    end
end

-- Render selected item details below the grid
function slot_renderer.renderItemDetails(inventory, selected_slot, player, window_x, slot_size, slot_spacing, item_font, desc_font)
    if selected_slot < 1 or selected_slot > #inventory.items then
        return
    end

    local item = inventory.items[selected_slot]
    local start_y = 150
    local detail_y = start_y + math.ceil(#inventory.items / 5) * (slot_size + slot_spacing) + 30

    text_ui:draw(item.name, window_x + 30, detail_y, {1, 1, 1, 1}, item_font)
    text_ui:draw(item.description, window_x + 30, detail_y + 25, {0.8, 0.8, 0.8, 1}, desc_font)

    -- Draw usage instructions
    text_ui:draw("Press [E], [Q], [Space] or [Enter] to use", window_x + 30, detail_y + 50, {0.6, 0.8, 1, 1}, desc_font)

    -- Can use indicator
    if item:canUse(player) then
        text_ui:draw("✓ Can use", window_x + 30, detail_y + 70, {0.3, 1, 0.3, 1}, desc_font)
    else
        text_ui:draw("✗ Cannot use (HP full)", window_x + 30, detail_y + 70, {1, 0.3, 0.3, 1}, desc_font)
    end
end

return slot_renderer

-- scenes/inventory/slot_renderer.lua
-- Renders inventory slots, items, and UI elements

local slot_renderer = {}

-- Render the close button in the top-right corner
function slot_renderer.renderCloseButton(window_x, window_y, window_w, close_button_size, close_button_padding)
    local close_x = window_x + window_w - close_button_size - close_button_padding
    local close_y = window_y + close_button_padding

    -- Button background
    love.graphics.setColor(0.8, 0.2, 0.2, 0.8)
    love.graphics.rectangle("fill", close_x, close_y, close_button_size, close_button_size, 3, 3)

    -- Button border
    love.graphics.setColor(1, 0.3, 0.3, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", close_x, close_y, close_button_size, close_button_size, 3, 3)

    -- Draw X
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(3)
    local x_padding = 8
    love.graphics.line(
        close_x + x_padding, close_y + x_padding,
        close_x + close_button_size - x_padding, close_y + close_button_size - x_padding
    )
    love.graphics.line(
        close_x + close_button_size - x_padding, close_y + x_padding,
        close_x + x_padding, close_y + close_button_size - x_padding
    )
    love.graphics.setLineWidth(1)

    return { x = close_x, y = close_y, size = close_button_size }
end

-- Render the item grid with slots
function slot_renderer.renderItemGrid(inventory, selected_slot, slot_size, slot_spacing, title_font, item_font, desc_font)
    local screen = require "engine.display"
    local vw, vh = screen:GetVirtualDimensions()

    if #inventory.items == 0 then
        love.graphics.setFont(item_font)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        local empty_text = "No items in inventory"
        local empty_w = item_font:getWidth(empty_text)
        love.graphics.print(empty_text, (vw - empty_w) / 2, vh / 2)
        return
    end

    local start_x = (vw - (slot_size + slot_spacing) * math.min(#inventory.items, 5)) / 2
    local start_y = 150

    for i, item in ipairs(inventory.items) do
        local row = math.floor((i - 1) / 5)
        local col = (i - 1) % 5
        local x = start_x + col * (slot_size + slot_spacing)
        local y = start_y + row * (slot_size + slot_spacing)

        -- Draw slot background
        if i == selected_slot then
            love.graphics.setColor(0.4, 0.6, 1, 0.9)
        else
            love.graphics.setColor(0.2, 0.2, 0.3, 0.8)
        end
        love.graphics.rectangle("fill", x, y, slot_size, slot_size, 5, 5)

        -- Draw slot border
        if i == selected_slot then
            love.graphics.setColor(0.6, 0.8, 1, 1)
            love.graphics.setLineWidth(3)
        else
            love.graphics.setColor(0.4, 0.4, 0.5, 1)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", x, y, slot_size, slot_size, 5, 5)

        -- Draw item icon (colored HP text)
        love.graphics.setFont(title_font)
        local icon_text = "HP"
        if item.type == "small_potion" then
            love.graphics.setColor(0.5, 1, 0.5, 1)
        elseif item.type == "large_potion" then
            love.graphics.setColor(0.3, 1, 0.8, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        local icon_w = title_font:getWidth(icon_text)
        love.graphics.print(icon_text, x + (slot_size - icon_w) / 2, y + 15)

        -- Draw quantity
        love.graphics.setFont(item_font)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("x" .. item.quantity, x + 8, y + slot_size - 25)

        -- Draw slot number
        love.graphics.setFont(desc_font)
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(tostring(i), x + 5, y + 5)
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

    love.graphics.setFont(item_font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(item.name, window_x + 30, detail_y)

    love.graphics.setFont(desc_font)
    love.graphics.setColor(0.8, 0.8, 0.8, 1)
    love.graphics.print(item.description, window_x + 30, detail_y + 25)

    -- Draw usage instructions
    love.graphics.setColor(0.6, 0.8, 1, 1)
    love.graphics.print("Press [E], [Q], [Space] or [Enter] to use", window_x + 30, detail_y + 50)

    -- Can use indicator
    if item:canUse(player) then
        love.graphics.setColor(0.3, 1, 0.3, 1)
        love.graphics.print("✓ Can use", window_x + 30, detail_y + 70)
    else
        love.graphics.setColor(1, 0.3, 0.3, 1)
        love.graphics.print("✗ Cannot use (HP full)", window_x + 30, detail_y + 70)
    end
end

return slot_renderer

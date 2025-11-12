-- engine/ui/screens/inventory/inventory_renderer.lua
-- Renders grid-based inventory with items occupying multiple cells

local slot_renderer = {}
local shapes = require "engine.utils.shapes"
local text_ui = require "engine.utils.text"
local input = require "engine.core.input"

-- Grid constants
local CELL_SIZE = 50
local CELL_SPACING = 2

-- Render the close button in the top-right corner
function slot_renderer.renderCloseButton(window_x, window_y, window_w, close_button_size, close_button_padding, is_hovered)
    local close_x = window_x + window_w - close_button_size - close_button_padding
    local close_y = window_y + close_button_padding

    shapes:drawCloseButton(close_x, close_y, close_button_size, is_hovered or false)

    return { x = close_x, y = close_y, size = close_button_size }
end

-- Calculate grid start position (right side, next to equipment slots)
function slot_renderer.getGridStartPosition(grid_width, grid_height, window_y, window_x)
    -- Equipment slots take up left side (approx 130px width + 20px margin)
    -- Position grid to the right of equipment slots
    local equipment_width = 130  -- 2 columns of 60px slots + 10px spacing
    local left_margin = 20
    local spacing_between = 30  -- Gap between equipment and grid

    local start_x = window_x + left_margin + equipment_width + spacing_between
    local start_y = window_y + 70  -- Title at +20, grid starts at +70 (50px gap)

    return start_x, start_y
end

-- Convert grid coordinates to screen coordinates
function slot_renderer.gridToScreen(grid_x, grid_y, start_x, start_y)
    local screen_x = start_x + (grid_x - 1) * (CELL_SIZE + CELL_SPACING)
    local screen_y = start_y + (grid_y - 1) * (CELL_SIZE + CELL_SPACING)
    return screen_x, screen_y
end

-- Convert screen coordinates to grid coordinates
function slot_renderer.screenToGrid(screen_x, screen_y, start_x, start_y)
    local grid_x = math.floor((screen_x - start_x) / (CELL_SIZE + CELL_SPACING)) + 1
    local grid_y = math.floor((screen_y - start_y) / (CELL_SIZE + CELL_SPACING)) + 1
    return grid_x, grid_y
end

-- Render the item grid with cells
function slot_renderer.renderItemGrid(inventory, selected_item_id, title_font, item_font, desc_font, drag_state, window_x, window_y, cursor_mode, cursor_x, cursor_y, gamepad_drag)
    local display = require "engine.core.display"
    local vw, vh = display:GetVirtualDimensions()

    local start_x, start_y = slot_renderer.getGridStartPosition(inventory.grid_width, inventory.grid_height, window_y, window_x)

    -- Check if inventory is empty
    local item_count = 0
    for _ in pairs(inventory.items) do
        item_count = item_count + 1
    end

    if item_count == 0 then
        -- Draw empty grid cells
        for y = 1, inventory.grid_height do
            for x = 1, inventory.grid_width do
                local screen_x, screen_y = slot_renderer.gridToScreen(x, y, start_x, start_y)
                shapes:drawSlot(screen_x, screen_y, CELL_SIZE, false, false, 3)
            end
        end

        -- Draw empty message
        local empty_text = "No items in inventory"
        local empty_w = item_font:getWidth(empty_text)
        text_ui:draw(empty_text, (vw - empty_w) / 2, start_y + 200, {0.5, 0.5, 0.5, 1}, item_font)
        return start_x, start_y
    end

    -- Draw grid background cells
    for y = 1, inventory.grid_height do
        for x = 1, inventory.grid_width do
            local screen_x, screen_y = slot_renderer.gridToScreen(x, y, start_x, start_y)

            -- Draw cell background (slightly darker for occupied cells)
            local is_occupied = inventory.grid[y][x] ~= nil
            if is_occupied then
                shapes:drawSlot(screen_x, screen_y, CELL_SIZE, false, false, 2)
            else
                shapes:drawSlot(screen_x, screen_y, CELL_SIZE, false, false, 3)
            end
        end
    end

    -- Draw items (each item occupies multiple cells)
    for item_id, item_data in pairs(inventory.items) do
        -- Skip if this is the item being dragged (mouse or gamepad)
        if (drag_state and drag_state.active and item_id == drag_state.item_id) or
           (gamepad_drag and gamepad_drag.active and item_id == gamepad_drag.item_id) then
            -- Don't render in grid, will be rendered at drag position
        else
            local screen_x, screen_y = slot_renderer.gridToScreen(item_data.x, item_data.y, start_x, start_y)
            local item_w = item_data.width * CELL_SIZE + (item_data.width - 1) * CELL_SPACING
            local item_h = item_data.height * CELL_SIZE + (item_data.height - 1) * CELL_SPACING

            -- Draw item background (covers multiple cells)
            local is_selected = (item_id == selected_item_id)
            shapes:drawSlot(screen_x, screen_y, item_w, item_h, is_selected, true, 5)

        -- Draw item icon (colored box with type indicator)
        local item = item_data.item
        local icon_text = "HP"  -- All potions show "HP"
        local icon_color

        if item.type == "small_potion" then
            icon_color = {0.5, 1, 0.5, 1}  -- Green
        elseif item.type == "large_potion" then
            icon_color = {0.3, 1, 0.8, 1}  -- Cyan
        else
            icon_color = {1, 1, 1, 1}  -- White
        end

        -- Center icon in item area
        local icon_w = title_font:getWidth(icon_text)
        local icon_x = screen_x + (item_w - icon_w) / 2
        local icon_y = screen_y + (item_h - title_font:getHeight()) / 2
        text_ui:draw(icon_text, icon_x, icon_y, icon_color, title_font)

        -- Draw quantity (bottom-left corner)
        if item.quantity > 1 then
            text_ui:draw("x" .. item.quantity, screen_x + 5, screen_y + item_h - 20, {1, 1, 1, 1}, desc_font)
        end

            -- Draw size indicator (top-right corner, for debugging)
            local size_text = string.format("%dx%d", item_data.width, item_data.height)
            local size_w = desc_font:getWidth(size_text)
            text_ui:draw(size_text, screen_x + item_w - size_w - 5, screen_y + 5, {0.7, 0.7, 0.7, 0.7}, desc_font)
        end
    end

    -- Draw dragged item (follows mouse, with placement preview)
    if drag_state and drag_state.active then
        slot_renderer.renderDraggedItem(inventory, drag_state, start_x, start_y, title_font, item_font, desc_font)
    end

    -- Draw gamepad dragged item (at cursor position, with placement preview)
    if gamepad_drag and gamepad_drag.active then
        slot_renderer.renderGamepadDraggedItem(inventory, gamepad_drag, cursor_x, cursor_y, start_x, start_y, title_font, item_font, desc_font)
    end

    -- Draw gamepad cursor (if cursor mode enabled)
    if cursor_mode then
        local cursor_screen_x, cursor_screen_y = slot_renderer.gridToScreen(cursor_x, cursor_y, start_x, start_y)

        -- Yellow border for cursor
        love.graphics.setColor(1, 1, 0, 0.8)  -- Yellow
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", cursor_screen_x - 2, cursor_screen_y - 2, CELL_SIZE + 4, CELL_SIZE + 4)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)
    end

    return start_x, start_y
end

-- Render dragged item at mouse position with placement preview
function slot_renderer.renderDraggedItem(inventory, drag_state, grid_start_x, grid_start_y, title_font, item_font, desc_font)
    -- Get item from drag state (stored when drag started)
    local item_obj = drag_state.item_obj

    if not item_obj then
        return
    end

    local CELL_SIZE, CELL_SPACING = slot_renderer.getGridConstants()

    -- Calculate item position at mouse (adjusted for offset)
    local item_screen_x = drag_state.visual_x - drag_state.offset_x
    local item_screen_y = drag_state.visual_y - drag_state.offset_y

    local item_w = drag_state.origin_width * CELL_SIZE + (drag_state.origin_width - 1) * CELL_SPACING
    local item_h = drag_state.origin_height * CELL_SIZE + (drag_state.origin_height - 1) * CELL_SPACING

    -- Calculate which grid cell the item would be placed in
    local drop_grid_x, drop_grid_y = slot_renderer.screenToGrid(item_screen_x, item_screen_y, grid_start_x, grid_start_y)

    -- Check if placement is valid
    local can_place = inventory:canPlaceItem(drop_grid_x, drop_grid_y, drag_state.origin_width, drag_state.origin_height)

    -- Draw placement preview (highlight cells)
    if drop_grid_x >= 1 and drop_grid_x <= inventory.grid_width and
       drop_grid_y >= 1 and drop_grid_y <= inventory.grid_height then
        -- Draw highlight on cells where item would be placed
        for dy = 0, drag_state.origin_height - 1 do
            for dx = 0, drag_state.origin_width - 1 do
                local cell_x = drop_grid_x + dx
                local cell_y = drop_grid_y + dy

                if cell_x >= 1 and cell_x <= inventory.grid_width and
                   cell_y >= 1 and cell_y <= inventory.grid_height then
                    local cell_screen_x, cell_screen_y = slot_renderer.gridToScreen(cell_x, cell_y, grid_start_x, grid_start_y)

                    -- Draw highlight (green if valid, red if invalid)
                    if can_place then
                        love.graphics.setColor(0.3, 1, 0.3, 0.3)  -- Green
                    else
                        love.graphics.setColor(1, 0.3, 0.3, 0.3)  -- Red
                    end
                    love.graphics.rectangle("fill", cell_screen_x, cell_screen_y, CELL_SIZE, CELL_SIZE)
                end
            end
        end
    end

    -- Draw dragged item (semi-transparent)
    love.graphics.setColor(1, 1, 1, 0.7)
    shapes:drawSlot(item_screen_x, item_screen_y, item_w, item_h, false, true, 5)

    -- Draw item icon
    local icon_text = "HP"
    local icon_color

    if item_obj.type == "small_potion" then
        icon_color = {0.5, 1, 0.5, 0.7}  -- Green, semi-transparent
    elseif item_obj.type == "large_potion" then
        icon_color = {0.3, 1, 0.8, 0.7}  -- Cyan, semi-transparent
    else
        icon_color = {1, 1, 1, 0.7}
    end

    local icon_w = title_font:getWidth(icon_text)
    local icon_x = item_screen_x + (item_w - icon_w) / 2
    local icon_y = item_screen_y + (item_h - title_font:getHeight()) / 2
    text_ui:draw(icon_text, icon_x, icon_y, icon_color, title_font)

    -- Draw quantity
    if item_obj.quantity > 1 then
        text_ui:draw("x" .. item_obj.quantity, item_screen_x + 5, item_screen_y + item_h - 20, {1, 1, 1, 0.7}, desc_font)
    end

    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Render gamepad dragged item at cursor position
function slot_renderer.renderGamepadDraggedItem(inventory, gamepad_drag, cursor_x, cursor_y, grid_start_x, grid_start_y, title_font, item_font, desc_font)
    local item_obj = gamepad_drag.item_obj
    if not item_obj then
        return
    end

    local CELL_SIZE, CELL_SPACING = slot_renderer.getGridConstants()

    -- Calculate item position at cursor
    local item_screen_x, item_screen_y = slot_renderer.gridToScreen(cursor_x, cursor_y, grid_start_x, grid_start_y)
    local item_w = gamepad_drag.origin_width * CELL_SIZE + (gamepad_drag.origin_width - 1) * CELL_SPACING
    local item_h = gamepad_drag.origin_height * CELL_SIZE + (gamepad_drag.origin_height - 1) * CELL_SPACING

    -- Check if placement is valid
    local can_place = inventory:canPlaceItem(cursor_x, cursor_y, gamepad_drag.origin_width, gamepad_drag.origin_height)

    -- Draw highlight on cells where item would be placed
    for dy = 0, gamepad_drag.origin_height - 1 do
        for dx = 0, gamepad_drag.origin_width - 1 do
            local cell_x = cursor_x + dx
            local cell_y = cursor_y + dy

            if cell_x >= 1 and cell_x <= inventory.grid_width and
               cell_y >= 1 and cell_y <= inventory.grid_height then
                local cell_screen_x, cell_screen_y = slot_renderer.gridToScreen(cell_x, cell_y, grid_start_x, grid_start_y)

                -- Draw highlight (green if valid, red if invalid)
                if can_place then
                    love.graphics.setColor(0.3, 1, 0.3, 0.3)  -- Green
                else
                    love.graphics.setColor(1, 0.3, 0.3, 0.3)  -- Red
                end
                love.graphics.rectangle("fill", cell_screen_x, cell_screen_y, CELL_SIZE, CELL_SIZE)
            end
        end
    end

    -- Draw dragged item (semi-transparent)
    love.graphics.setColor(1, 1, 1, 0.7)
    local shapes = require "engine.utils.shapes"
    shapes:drawSlot(item_screen_x, item_screen_y, item_w, item_h, false, true, 5)

    -- Draw item icon
    local icon_text = "HP"
    local icon_color

    if item_obj.type == "small_potion" then
        icon_color = {0.5, 1, 0.5, 0.7}  -- Green, semi-transparent
    elseif item_obj.type == "large_potion" then
        icon_color = {0.3, 1, 0.8, 0.7}  -- Cyan, semi-transparent
    else
        icon_color = {1, 1, 1, 0.7}
    end

    local icon_w = title_font:getWidth(icon_text)
    local icon_x = item_screen_x + (item_w - icon_w) / 2
    local icon_y = item_screen_y + (item_h - title_font:getHeight()) / 2
    local text_ui = require "engine.utils.text"
    text_ui:draw(icon_text, icon_x, icon_y, icon_color, title_font)

    -- Draw quantity
    if item_obj.quantity > 1 then
        text_ui:draw("x" .. item_obj.quantity, item_screen_x + 5, item_screen_y + item_h - 20, {1, 1, 1, 0.7}, desc_font)
    end

    -- Reset color
    love.graphics.setColor(1, 1, 1, 1)
end

-- Render selected item details below the grid
function slot_renderer.renderItemDetails(inventory, selected_item_id, player, window_x, window_y, grid_start_y, item_font, desc_font)
    if not selected_item_id then
        return
    end

    local item_data = inventory.items[selected_item_id]
    if not item_data then
        return
    end

    local item = item_data.item
    local detail_y = grid_start_y + inventory.grid_height * (CELL_SIZE + CELL_SPACING) + 15

    -- Line 1: Item name - Description
    local line1 = string.format("%s - %s", item.name, item.description)
    text_ui:draw(line1, window_x + 30, detail_y, {1, 1, 1, 1}, item_font)

    -- Line 2: Position | Size | Status (all in one line)
    local status_text
    local status_color
    if item:canUse(player) then
        status_text = "✓ Can use"
        status_color = {0.3, 1, 0.3, 1}
    else
        status_text = "✗ Cannot use (HP full)"
        status_color = {1, 0.3, 0.3, 1}
    end

    local line2 = string.format("Pos: (%d,%d) | Size: %dx%d | ",
        item_data.x, item_data.y, item_data.width, item_data.height)

    -- Draw position/size in gray
    text_ui:draw(line2, window_x + 30, detail_y + 22, {0.6, 0.6, 0.6, 1}, desc_font)

    -- Draw status next to it in color
    local line2_width = desc_font:getWidth(line2)
    text_ui:draw(status_text, window_x + 30 + line2_width, detail_y + 22, status_color, desc_font)
end

-- Get grid constants (for use in other modules)
function slot_renderer.getGridConstants()
    return CELL_SIZE, CELL_SPACING
end

-- Render equipment slots panel (left side of inventory)
function slot_renderer.renderEquipmentSlots(inventory, window_x, window_y, title_font, item_font, desc_font)
    local SLOT_SIZE = 60
    local SLOT_SPACING = 10
    local panel_x = window_x + 20
    local panel_y = window_y + 70

    -- Equipment slot layout (2 columns)
    local slot_layout = {
        { name = "helmet", x = 0, y = 0, label = "Helmet" },
        { name = "chest", x = 0, y = 1, label = "Chest" },
        { name = "weapon", x = 1, y = 0, label = "Weapon" },
        { name = "shield", x = 1, y = 1, label = "Shield" },
        { name = "gloves", x = 0, y = 2, label = "Gloves" },
        { name = "boots", x = 0, y = 3, label = "Boots" },
        { name = "ring1", x = 1, y = 2, label = "Ring 1" },
        { name = "ring2", x = 1, y = 3, label = "Ring 2" },
    }

    for _, slot_info in ipairs(slot_layout) do
        local slot_x = panel_x + slot_info.x * (SLOT_SIZE + SLOT_SPACING)
        local slot_y = panel_y + slot_info.y * (SLOT_SIZE + SLOT_SPACING)

        -- Draw slot background
        shapes:drawSlot(slot_x, slot_y, SLOT_SIZE, SLOT_SIZE, false, false, 5)

        -- Draw slot label above
        local label_w = desc_font:getWidth(slot_info.label)
        text_ui:draw(slot_info.label, slot_x + (SLOT_SIZE - label_w) / 2, slot_y - 18, {0.7, 0.7, 0.7, 1}, desc_font)

        -- Draw equipped item (if any)
        local item_id = inventory.equipment_slots[slot_info.name]
        if item_id then
            local item_data = inventory.items[item_id]
            if item_data and item_data.item then
                local item = item_data.item

                -- Draw actual item sprite (if available)
                if item.sprite and item.sprite.file then
                    -- Load sprite sheet (cached by LÖVE)
                    local sprite_sheet = love.graphics.newImage(item.sprite.file)

                    -- Create quad for item sprite
                    local quad = love.graphics.newQuad(
                        item.sprite.x,
                        item.sprite.y,
                        item.sprite.w,
                        item.sprite.h,
                        sprite_sheet:getWidth(),
                        sprite_sheet:getHeight()
                    )

                    -- Calculate centered position
                    local sprite_w = item.sprite.w * item.sprite.scale
                    local sprite_h = item.sprite.h * item.sprite.scale
                    local sprite_x = slot_x + (SLOT_SIZE - sprite_w) / 2
                    local sprite_y = slot_y + (SLOT_SIZE - sprite_h) / 2

                    -- Draw sprite
                    love.graphics.setColor(1, 1, 1, 1)
                    love.graphics.draw(sprite_sheet, quad, sprite_x, sprite_y, 0, item.sprite.scale, item.sprite.scale)
                else
                    -- Fallback: text icon
                    local icon_text = "⚔"
                    if slot_info.name == "helmet" then icon_text = "🪖"
                    elseif slot_info.name == "chest" then icon_text = "🛡"
                    elseif slot_info.name == "weapon" then icon_text = "⚔"
                    elseif slot_info.name == "shield" then icon_text = "🛡"
                    elseif slot_info.name:match("ring") then icon_text = "💍"
                    elseif slot_info.name == "boots" then icon_text = "👢"
                    elseif slot_info.name == "gloves" then icon_text = "🧤"
                    end

                    local icon_w = title_font:getWidth(icon_text)
                    local icon_x = slot_x + (SLOT_SIZE - icon_w) / 2
                    local icon_y = slot_y + (SLOT_SIZE - title_font:getHeight()) / 2
                    text_ui:draw(icon_text, icon_x, icon_y, {1, 1, 0.5, 1}, title_font)
                end
            end
        end
    end

    -- Return bounds for drag & drop detection
    return {
        x = panel_x,
        y = panel_y,
        width = 2 * (SLOT_SIZE + SLOT_SPACING) - SLOT_SPACING,
        height = 4 * (SLOT_SIZE + SLOT_SPACING) - SLOT_SPACING,
        slot_size = SLOT_SIZE,
        slot_spacing = SLOT_SPACING,
        layout = slot_layout
    }
end

return slot_renderer

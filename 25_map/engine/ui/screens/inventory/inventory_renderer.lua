-- engine/ui/screens/inventory/inventory_renderer.lua
-- Renders grid-based inventory with items occupying multiple cells

local slot_renderer = {}
local shapes = require "engine.utils.shapes"
local text_ui = require "engine.utils.text"
local input = require "engine.core.input"
local colors = require "engine.ui.colors"

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
        text_ui:draw(empty_text, (vw - empty_w) / 2, start_y + 200, colors.for_text_dim, item_font)
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
        -- Skip if this item is equipped (no grid position)
        elseif item_data.equipped or not item_data.x or not item_data.y then
            -- Don't render equipped items in grid
        else
            local screen_x, screen_y = slot_renderer.gridToScreen(item_data.x, item_data.y, start_x, start_y)
            local item_w = item_data.width * CELL_SIZE + (item_data.width - 1) * CELL_SPACING
            local item_h = item_data.height * CELL_SIZE + (item_data.height - 1) * CELL_SPACING

            -- Draw item border
            local is_selected = (item_id == selected_item_id)
            if is_selected then
                -- Selected item border
                love.graphics.setColor(colors.for_item_selected)
                love.graphics.setLineWidth(colors.BORDER_WIDTH_MEDIUM)
            else
                -- Normal item border
                love.graphics.setColor(colors.for_item_border)
                love.graphics.setLineWidth(colors.BORDER_WIDTH_THIN)
            end
            love.graphics.rectangle("line", screen_x, screen_y, item_w, item_h, 5, 5)
            love.graphics.setLineWidth(1)
            colors:reset()

        -- Draw item icon/sprite
        local item = item_data.item

        -- If item has sprite data, render the actual sprite
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
            local sprite_x = screen_x + (item_w - sprite_w) / 2
            local sprite_y = screen_y + (item_h - sprite_h) / 2

            -- Draw sprite
            colors:apply(colors.WHITE)
            love.graphics.draw(sprite_sheet, quad, sprite_x, sprite_y, 0, item.sprite.scale, item.sprite.scale)
        else
            -- Fallback: text icon (for potions without sprites)
            local icon_text = "HP"  -- Default for potions
            -- Use item's color property if available, otherwise default to normal text color
            local icon_color = item.color or colors.for_text_normal

            -- Center icon in item area
            local icon_w = title_font:getWidth(icon_text)
            local icon_x = screen_x + (item_w - icon_w) / 2
            local icon_y = screen_y + (item_h - title_font:getHeight()) / 2
            text_ui:draw(icon_text, icon_x, icon_y, icon_color, title_font)
        end

        -- Draw quantity (bottom-left corner)
        if item.quantity > 1 then
            text_ui:draw("x" .. item.quantity, screen_x + 5, screen_y + item_h - 20, colors.for_text_normal, desc_font)
        end

        -- Draw size indicator (top-right corner, for debugging)
        local size_text = string.format("%dx%d", item_data.width, item_data.height)
        local size_w = desc_font:getWidth(size_text)
        local size_color = colors:withAlpha(colors.for_text_mid_gray, 0.7)
        text_ui:draw(size_text, screen_x + item_w - size_w - 5, screen_y + 5, size_color, desc_font)
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

        -- Gamepad cursor border
        colors:apply(colors.for_gamepad_cursor)
        love.graphics.setLineWidth(colors.BORDER_WIDTH_THICK)
        love.graphics.rectangle("line", cursor_screen_x - 2, cursor_screen_y - 2, CELL_SIZE + 4, CELL_SIZE + 4)
        love.graphics.setLineWidth(1)
        colors:reset()
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

    -- For natural drag & drop, use first cell's center (not the entire item's center)
    -- This prevents multi-cell items from "sinking down" due to their center being in the next cell
    local snap_point_x = item_screen_x + CELL_SIZE / 2
    local snap_point_y = item_screen_y + CELL_SIZE / 2

    -- Calculate which grid cell the snap point would be placed in
    local drop_grid_x, drop_grid_y = slot_renderer.screenToGrid(snap_point_x, snap_point_y, grid_start_x, grid_start_y)

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
                    colors:apply(can_place and colors.for_placement_valid or colors.for_placement_invalid)
                    love.graphics.rectangle("fill", cell_screen_x, cell_screen_y, CELL_SIZE, CELL_SIZE)
                end
            end
        end
    end

    -- Draw dragged item (semi-transparent)
    colors:apply(colors.WHITE, 0.7)
    shapes:drawSlot(item_screen_x, item_screen_y, item_w, item_h, false, true, 5)

    -- Draw item icon/sprite
    if item_obj.sprite and item_obj.sprite.file then
        -- Draw sprite for equipment
        local sprite_sheet = love.graphics.newImage(item_obj.sprite.file)
        local quad = love.graphics.newQuad(
            item_obj.sprite.x,
            item_obj.sprite.y,
            item_obj.sprite.w,
            item_obj.sprite.h,
            sprite_sheet:getWidth(),
            sprite_sheet:getHeight()
        )

        local sprite_w = item_obj.sprite.w * item_obj.sprite.scale
        local sprite_h = item_obj.sprite.h * item_obj.sprite.scale
        local sprite_x = item_screen_x + (item_w - sprite_w) / 2
        local sprite_y = item_screen_y + (item_h - sprite_h) / 2

        colors:apply(colors.WHITE, 0.7)
        love.graphics.draw(sprite_sheet, quad, sprite_x, sprite_y, 0, item_obj.sprite.scale, item_obj.sprite.scale)
    else
        -- Fallback: text icon for potions
        local icon_text = "HP"
        -- Use item's color property with 0.7 alpha, or default to semi-transparent white
        local icon_color = item_obj.color and colors:withAlpha(item_obj.color, 0.7) or colors:withAlpha(colors.WHITE, 0.7)

        local icon_w = title_font:getWidth(icon_text)
        local icon_x = item_screen_x + (item_w - icon_w) / 2
        local icon_y = item_screen_y + (item_h - title_font:getHeight()) / 2
        text_ui:draw(icon_text, icon_x, icon_y, icon_color, title_font)
    end

    -- Draw quantity
    if item_obj.quantity > 1 then
        text_ui:draw("x" .. item_obj.quantity, item_screen_x + 5, item_screen_y + item_h - 20, colors:withAlpha(colors.WHITE, 0.7), desc_font)
    end

    colors:reset()
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
                colors:apply(can_place and colors.for_placement_valid or colors.for_placement_invalid)
                love.graphics.rectangle("fill", cell_screen_x, cell_screen_y, CELL_SIZE, CELL_SIZE)
            end
        end
    end

    -- Draw dragged item (semi-transparent)
    colors:apply(colors.WHITE, 0.7)
    local shapes = require "engine.utils.shapes"
    shapes:drawSlot(item_screen_x, item_screen_y, item_w, item_h, false, true, 5)

    local text_ui = require "engine.utils.text"

    -- Draw item icon/sprite
    if item_obj.sprite and item_obj.sprite.file then
        -- Draw sprite for equipment
        local sprite_sheet = love.graphics.newImage(item_obj.sprite.file)
        local quad = love.graphics.newQuad(
            item_obj.sprite.x,
            item_obj.sprite.y,
            item_obj.sprite.w,
            item_obj.sprite.h,
            sprite_sheet:getWidth(),
            sprite_sheet:getHeight()
        )

        local sprite_w = item_obj.sprite.w * item_obj.sprite.scale
        local sprite_h = item_obj.sprite.h * item_obj.sprite.scale
        local sprite_x = item_screen_x + (item_w - sprite_w) / 2
        local sprite_y = item_screen_y + (item_h - sprite_h) / 2

        colors:apply(colors.WHITE, 0.7)
        love.graphics.draw(sprite_sheet, quad, sprite_x, sprite_y, 0, item_obj.sprite.scale, item_obj.sprite.scale)
    else
        -- Fallback: text icon for potions
        local icon_text = "HP"
        -- Use item's color property with 0.7 alpha, or default to semi-transparent white
        local icon_color = item_obj.color and colors:withAlpha(item_obj.color, 0.7) or colors:withAlpha(colors.WHITE, 0.7)

        local icon_w = title_font:getWidth(icon_text)
        local icon_x = item_screen_x + (item_w - icon_w) / 2
        local icon_y = item_screen_y + (item_h - title_font:getHeight()) / 2
        text_ui:draw(icon_text, icon_x, icon_y, icon_color, title_font)
    end

    -- Draw quantity
    if item_obj.quantity > 1 then
        text_ui:draw("x" .. item_obj.quantity, item_screen_x + 5, item_screen_y + item_h - 20, colors:withAlpha(colors.WHITE, 0.7), desc_font)
    end

    colors:reset()
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
    local detail_y = grid_start_y + inventory.grid_height * (CELL_SIZE + CELL_SPACING) + 5

    -- Calculate detail X position (aligned with grid left edge)
    local equipment_width = 130
    local left_margin = 20
    local spacing_between = 30
    local detail_x = window_x + left_margin + equipment_width + spacing_between

    -- Line 1: Item name - Description
    local line1 = string.format("%s - %s", item.name, item.description)
    text_ui:draw(line1, detail_x, detail_y, colors.for_text_normal, item_font)

    -- Line 2: Position | Size | Status (all in one line)
    local status_text
    local status_color

    -- Check if this is equipment
    if item.item_type == "equipment" then
        status_text = "⚔ Equipment (drag to slot)"
        status_color = colors.for_item_equipment
    elseif item:canUse(player) then
        status_text = "✓ Can use"
        status_color = colors.for_item_usable
    else
        status_text = "✗ Cannot use (HP full)"
        status_color = colors.for_item_unusable
    end

    -- Build line2 (position/size info)
    local line2
    if item_data.equipped then
        -- Equipped item: show slot and size only
        line2 = string.format("Equipped: %s | Size: %dx%d | ",
            item_data.slot or "unknown", item_data.width, item_data.height)
    elseif item_data.x and item_data.y then
        -- Grid item: show position and size
        line2 = string.format("Pos: (%d,%d) | Size: %dx%d | ",
            item_data.x, item_data.y, item_data.width, item_data.height)
    else
        -- Fallback: size only
        line2 = string.format("Size: %dx%d | ", item_data.width, item_data.height)
    end

    -- Draw position/size in gray (aligned with grid)
    text_ui:draw(line2, detail_x, detail_y + 22, colors.for_text_dark_gray, desc_font)

    -- Draw status next to it in color
    local line2_width = desc_font:getWidth(line2)
    text_ui:draw(status_text, detail_x + line2_width, detail_y + 22, status_color, desc_font)
end

-- Get grid constants (for use in other modules)
function slot_renderer.getGridConstants()
    return CELL_SIZE, CELL_SPACING
end

-- Render equipment slots panel (left side of inventory)
function slot_renderer.renderEquipmentSlots(inventory, window_x, window_y, title_font, item_font, desc_font, equipment_mode, equipment_cursor_x, equipment_cursor_y, drag_state)
    local SLOT_SIZE = 60
    local SLOT_SPACING = 10
    local panel_x = window_x + 20
    local panel_y = window_y + 70 + title_font:getHeight()

    -- Equipment slot layout (2 columns)
    local slot_layout = {
        { name = "helmet", x = 0, y = 0, label = "Helmet" },
        { name = "chest", x = 0, y = 1, label = "Chest" },
        { name = "weapon", x = 1, y = 0, label = "Weapon" },
        { name = "shield", x = 1, y = 1, label = "Shield" },
        { name = "gloves", x = 0, y = 2, label = "Gloves" },
        { name = "boots", x = 1, y = 2, label = "Boots" },
        { name = "bracelet", x = 0, y = 3, label = "Bracelet" },
        { name = "ring", x = 1, y = 3, label = "Ring" },
    }

    -- Get mouse position for drag-over detection
    local display = require "engine.core.display"
    local vmx, vmy = display:GetVirtualMousePosition()

    for _, slot_info in ipairs(slot_layout) do
        local slot_x = panel_x + slot_info.x * (SLOT_SIZE + SLOT_SPACING)
        -- Add label height for each row to prevent overlap
        local slot_y = panel_y + slot_info.y * (SLOT_SIZE + SLOT_SPACING + item_font:getHeight())

        -- Check if cursor is on this slot
        local is_cursor_here = equipment_mode and
                                equipment_cursor_x == slot_info.x and
                                equipment_cursor_y == slot_info.y

        -- Check if dragging item over this slot
        local is_drag_over = false
        local can_equip_here = false
        if drag_state and drag_state.active and drag_state.item_obj then
            -- Check if mouse is over this slot
            if vmx >= slot_x and vmx < slot_x + SLOT_SIZE and
               vmy >= slot_y and vmy < slot_y + SLOT_SIZE then
                is_drag_over = true

                -- Check if dragged item can be equipped to this slot
                local item = drag_state.item_obj
                if item.equipment_slot then
                    can_equip_here = item.equipment_slot == slot_info.name
                end
            end
        end

        -- Draw slot background (highlight if cursor is here or dragging over)
        local highlight = is_cursor_here or (is_drag_over and can_equip_here)
        shapes:drawSlot(slot_x, slot_y, SLOT_SIZE, SLOT_SIZE, false, highlight, 5)

        -- Draw drag-over highlight (green if can equip, red if cannot)
        if is_drag_over and not equipment_mode then
            colors:apply(can_equip_here and colors.for_placement_valid or colors.for_placement_invalid)
            love.graphics.rectangle("fill", slot_x, slot_y, SLOT_SIZE, SLOT_SIZE)
            colors:reset()
        end

        -- Draw slot label above
        local label_w = desc_font:getWidth(slot_info.label)
        text_ui:draw(slot_info.label, slot_x + (SLOT_SIZE - label_w) / 2, slot_y - 18, colors.for_text_mid_gray, desc_font)

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
                    colors:apply(colors.WHITE)
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
                    text_ui:draw(icon_text, icon_x, icon_y, colors.for_equipment_icon_fallback, title_font)
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

-- Render quickslots at bottom of inventory
function slot_renderer.renderQuickslots(inventory, window_x, window_y, window_w, window_h, player, drag_state, quickslot_hold, quickslot_mode, quickslot_cursor)
    local QUICK_SLOT_SIZE = 50
    local QUICK_SLOT_SPACING = 10
    local QUICK_SLOT_COUNT = 5

    -- Calculate position (centered at bottom of window)
    local total_width = QUICK_SLOT_COUNT * QUICK_SLOT_SIZE + (QUICK_SLOT_COUNT - 1) * QUICK_SLOT_SPACING
    local start_x = window_x + (window_w - total_width) / 2
    local start_y = window_y + window_h - QUICK_SLOT_SIZE - 15  -- 15px from bottom (half text line gap below description)

    -- Store bounds for interaction
    local quickslot_bounds = {}

    for i = 1, QUICK_SLOT_COUNT do
        local x = start_x + (i - 1) * (QUICK_SLOT_SIZE + QUICK_SLOT_SPACING)
        local y = start_y

        -- Get item in this quickslot
        local item_id = inventory.quickslots[i]
        local item_data = item_id and inventory.items[item_id]
        local item = item_data and item_data.item

        -- Check if this slot can accept the dragged item
        local can_drop = false
        if drag_state and drag_state.active and drag_state.item_obj then
            local dragged_item = drag_state.item_obj
            -- Only consumable items (not equipment)
            local is_equipment = dragged_item.equipment_slot or dragged_item.item_type == "equipment"
            can_drop = dragged_item.use and dragged_item.canUse and not is_equipment
        end

        -- Highlight if can drop
        if can_drop then
            colors:apply(colors.BRIGHT_YELLOW, 0.3)
            love.graphics.rectangle("fill", x, y, QUICK_SLOT_SIZE, QUICK_SLOT_SIZE)
        end

        -- Draw slot background
        colors:apply(colors.for_quickslot_bg)
        love.graphics.rectangle("fill", x, y, QUICK_SLOT_SIZE, QUICK_SLOT_SIZE)

        -- Draw slot border (yellow if selected in quickslot mode)
        if quickslot_mode and quickslot_cursor == i then
            colors:apply(colors.for_quickslot_selected)
            love.graphics.setLineWidth(3)
        else
            colors:apply(colors.for_quickslot_border)
            love.graphics.setLineWidth(2)
        end
        love.graphics.rectangle("line", x, y, QUICK_SLOT_SIZE, QUICK_SLOT_SIZE)

        -- Draw key number
        colors:apply(colors.for_text_normal)
        love.graphics.print(tostring(i), x + 4, y + 4)

        -- Draw item if assigned (skip if being dragged)
        if item and item_id ~= (drag_state and drag_state.item_id) then
            local can_use = item.canUse and item:canUse(player)

            -- Draw sprite if available
            if item.sprite then
                local sprite_img = love.graphics.newImage(item.sprite.file)
                local sprite_x = item.sprite.x or 0
                local sprite_y = item.sprite.y or 0
                local sprite_w = item.sprite.w or 32
                local sprite_h = item.sprite.h or 32
                local sprite_scale = item.sprite.scale or 1

                local quad = love.graphics.newQuad(
                    sprite_x, sprite_y,
                    sprite_w, sprite_h,
                    sprite_img:getWidth(), sprite_img:getHeight()
                )

                local draw_x = x + (QUICK_SLOT_SIZE - sprite_w * sprite_scale) / 2
                local draw_y = y + (QUICK_SLOT_SIZE - sprite_h * sprite_scale) / 2

                colors:apply(can_use and colors.WHITE or colors.for_quickslot_unusable)

                love.graphics.draw(sprite_img, quad, draw_x, draw_y, 0, sprite_scale, sprite_scale)
            end

            -- Draw quantity if stackable
            if item.max_stack and item.max_stack > 1 and item_data.quantity then
                colors:apply(colors.for_text_normal)
                local qty_text = tostring(item_data.quantity)
                love.graphics.print(qty_text, x + QUICK_SLOT_SIZE - 20, y + QUICK_SLOT_SIZE - 16)
            end
        end

        -- Draw hold-to-remove progress indicator
        if quickslot_hold and quickslot_hold.active and quickslot_hold.slot_index == i then
            local progress = quickslot_hold.timer / quickslot_hold.duration
            progress = math.min(progress, 1.0)  -- Cap at 1.0

            -- Draw red overlay with increasing opacity
            colors:apply(colors.FULL_RED, 0.3 + progress * 0.4)
            love.graphics.rectangle("fill", x, y, QUICK_SLOT_SIZE, QUICK_SLOT_SIZE)

            -- Draw progress bar at bottom
            local bar_height = 4
            local bar_y = y + QUICK_SLOT_SIZE - bar_height
            colors:apply(colors.FULL_RED, 0.8)
            love.graphics.rectangle("fill", x, bar_y, QUICK_SLOT_SIZE * progress, bar_height)
        end

        -- Store bounds for hit detection
        quickslot_bounds[i] = {
            x = x,
            y = y,
            width = QUICK_SLOT_SIZE,
            height = QUICK_SLOT_SIZE
        }
    end

    colors:reset()
    love.graphics.setLineWidth(1)

    return quickslot_bounds
end

return slot_renderer

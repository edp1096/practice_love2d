-- engine/ui/screens/inventory/input/mouse.lua
-- Mouse input handling for inventory (drag & drop)

local mouse_input = {}

local coords = require "engine.core.coords"
local display = require "engine.core.display"
local slot_renderer = require "engine.ui.screens.inventory.inventory_renderer"

-- Handle mouse input
function mouse_input.mousepressed(self, x, y, button, helpers)
    -- Disable cursor mode when using mouse
    self.cursor_mode = false

    if button == 1 then
        -- Check if starting a drag
        local vx, vy = coords:physicalToVirtual(x, y, display)

        -- Check equipment slot clicks first
        if self.equipment_bounds then
            local eq_bounds = self.equipment_bounds

            if vx >= eq_bounds.x and vx <= eq_bounds.x + eq_bounds.width and
               vy >= eq_bounds.y and vy <= eq_bounds.y + eq_bounds.height then

                -- Find which slot was clicked
                for _, slot_info in ipairs(eq_bounds.layout) do
                    local slot_x = eq_bounds.x + slot_info.x * (eq_bounds.slot_size + eq_bounds.slot_spacing)
                    local slot_y = eq_bounds.y + slot_info.y * (eq_bounds.slot_size + eq_bounds.slot_spacing)

                    if vx >= slot_x and vx <= slot_x + eq_bounds.slot_size and
                       vy >= slot_y and vy <= slot_y + eq_bounds.slot_size then

                        -- Check if slot has an item
                        local item_id = self.inventory.equipment_slots[slot_info.name]
                        if item_id then
                            local item_data = self.inventory.items[item_id]
                            if item_data then
                                -- Unequip and start dragging
                                local success, err = self.inventory:unequipItem(slot_info.name, self.player)
                                if success then
                                    -- Item is now in grid, find it and start dragging
                                    item_data = self.inventory.items[item_id]  -- Refresh data (now has grid position)

                                    self.drag_state.active = true
                                    self.drag_state.item_id = item_id
                                    self.drag_state.item_obj = item_data.item
                                    self.drag_state.origin_x = item_data.x
                                    self.drag_state.origin_y = item_data.y
                                    self.drag_state.origin_width = item_data.width
                                    self.drag_state.origin_height = item_data.height
                                    self.drag_state.origin_rotated = item_data.rotated
                                    self.drag_state.visual_x = vx
                                    self.drag_state.visual_y = vy
                                    self.drag_state.offset_x = eq_bounds.slot_size / 2  -- Center on mouse
                                    self.drag_state.offset_y = eq_bounds.slot_size / 2

                                    -- Remove from grid again (for dragging)
                                    self.inventory:removeItem(item_id)

                                    helpers.play_sound("ui", "select")
                                    return
                                else
                                    helpers.play_sound("ui", "error")
                                    return
                                end
                            end
                        end
                        break
                    end
                end
            end
        end

        -- Check grid clicks
        local grid_x, grid_y = slot_renderer.screenToGrid(vx, vy, self.grid_start_x, self.grid_start_y)

        -- Check if clicking on an item in grid
        if grid_x >= 1 and grid_x <= self.inventory.grid_width and
           grid_y >= 1 and grid_y <= self.inventory.grid_height then
            local item_id = self.inventory.grid[grid_y][grid_x]

            if item_id then
                -- Start dragging
                local item_data = self.inventory.items[item_id]
                self.drag_state.active = true
                self.drag_state.item_id = item_id
                self.drag_state.item_obj = item_data.item  -- Store item object reference
                self.drag_state.origin_x = item_data.x
                self.drag_state.origin_y = item_data.y
                self.drag_state.origin_width = item_data.width
                self.drag_state.origin_height = item_data.height
                self.drag_state.origin_rotated = item_data.rotated
                self.drag_state.visual_x = vx
                self.drag_state.visual_y = vy

                -- Calculate offset (mouse position relative to item top-left)
                local item_screen_x, item_screen_y = slot_renderer.gridToScreen(item_data.x, item_data.y, self.grid_start_x, self.grid_start_y)
                self.drag_state.offset_x = vx - item_screen_x
                self.drag_state.offset_y = vy - item_screen_y

                -- Remove from grid temporarily (holding in hand)
                self.inventory:removeItem(item_id)

                helpers.play_sound("ui", "select")
                return
            end
        end

        -- Check quickslot clicks (to start dragging from quickslot)
        if self.quickslot_bounds then
            for slot_index, bounds in ipairs(self.quickslot_bounds) do
                if vx >= bounds.x and vx <= bounds.x + bounds.width and
                   vy >= bounds.y and vy <= bounds.y + bounds.height then

                    local item_id = self.inventory.quickslots[slot_index]
                    if item_id then
                        local item_data = self.inventory.items[item_id]
                        if item_data then
                            -- Start dragging from quickslot
                            self.drag_state.active = true
                            self.drag_state.item_id = item_id
                            self.drag_state.item_obj = item_data.item
                            self.drag_state.origin_x = item_data.x
                            self.drag_state.origin_y = item_data.y
                            self.drag_state.origin_width = item_data.width
                            self.drag_state.origin_height = item_data.height
                            self.drag_state.origin_rotated = item_data.rotated
                            self.drag_state.visual_x = vx
                            self.drag_state.visual_y = vy
                            self.drag_state.offset_x = bounds.width / 2
                            self.drag_state.offset_y = bounds.height / 2
                            self.drag_state.from_quickslot_index = slot_index  -- Remember source quickslot

                            -- Keep quickslot assignment (don't remove!)
                            -- Only remove from grid temporarily (holding in hand)
                            self.inventory:removeItem(item_id)

                            helpers.play_sound("ui", "select")
                            return
                        end
                    end
                    break
                end
            end
        end

        -- Not dragging, handle as normal click
        helpers.handleClick(self, x, y)
    elseif button == 2 then
        -- Right click: rotate item or use selected item
        local vx, vy = coords:physicalToVirtual(x, y, display)
        local grid_x, grid_y = slot_renderer.screenToGrid(vx, vy, self.grid_start_x, self.grid_start_y)

        -- Check if clicking on an item
        if grid_x >= 1 and grid_x <= self.inventory.grid_width and
           grid_y >= 1 and grid_y <= self.inventory.grid_height then
            local item_id = self.inventory.grid[grid_y][grid_x]

            if item_id then
                -- Rotate item
                if self.inventory:rotateItem(item_id) then
                    helpers.play_sound("ui", "select")  -- Rotation success
                else
                    helpers.play_sound("ui", "error")  -- Rotation failed (1x1 or no space)
                end
                return
            end
        end

        -- Check if right-clicking on quickslot (to start hold-to-remove)
        if self.quickslot_bounds then
            for slot_index, bounds in ipairs(self.quickslot_bounds) do
                if vx >= bounds.x and vx <= bounds.x + bounds.width and
                   vy >= bounds.y and vy <= bounds.y + bounds.height then

                    -- Start hold timer to remove item from quickslot
                    local item_id = self.inventory.quickslots[slot_index]
                    if item_id then
                        self.quickslot_hold.active = true
                        self.quickslot_hold.slot_index = slot_index
                        self.quickslot_hold.timer = 0
                        self.quickslot_hold.source = "mouse"
                    end
                    return
                end
            end
        end

        -- No item clicked, use selected item
        helpers.useSelectedItem(self)
    end
end

-- Handle mouse release (drop)
function mouse_input.mousereleased(self, x, y, button, helpers)
    if button == 1 and self.drag_state.active then
        -- Calculate drop position
        local vx, vy = coords:physicalToVirtual(x, y, display)

        -- Get item data from drag state
        local item_id = self.drag_state.item_id
        local item_obj = self.drag_state.item_obj
        local placed = false

        -- Check if dropping on equipment slot
        if self.equipment_bounds and item_obj and item_obj.equipment_slot then
            local eq_bounds = self.equipment_bounds

            -- Check if drop position is within equipment panel
            if vx >= eq_bounds.x and vx <= eq_bounds.x + eq_bounds.width and
               vy >= eq_bounds.y and vy <= eq_bounds.y + eq_bounds.height then

                -- Find which slot was clicked
                for _, slot_info in ipairs(eq_bounds.layout) do
                    local slot_x = eq_bounds.x + slot_info.x * (eq_bounds.slot_size + eq_bounds.slot_spacing)
                    local slot_y = eq_bounds.y + slot_info.y * (eq_bounds.slot_size + eq_bounds.slot_spacing)

                    if vx >= slot_x and vx <= slot_x + eq_bounds.slot_size and
                       vy >= slot_y and vy <= slot_y + eq_bounds.slot_size then

                        -- IMPORTANT: Place item back to grid first (equipItem needs item to exist)
                        self.inventory:placeItem(
                            item_id,
                            item_obj,
                            self.drag_state.origin_x,
                            self.drag_state.origin_y,
                            self.drag_state.origin_width,
                            self.drag_state.origin_height,
                            self.drag_state.origin_rotated
                        )

                        -- Try to equip to this slot
                        local success, err = self.inventory:equipItem(item_id, slot_info.name, self.player)
                        if success then
                            helpers.play_sound("ui", "select")
                            placed = true
                        else
                            -- Item is already back in grid, so just mark as placed
                            placed = true
                        end
                        break
                    end
                end
            end
        end

        -- Check if dropping on quickslot
        if not placed and self.quickslot_bounds and item_obj then
            for slot_index, bounds in ipairs(self.quickslot_bounds) do
                if vx >= bounds.x and vx <= bounds.x + bounds.width and
                   vy >= bounds.y and vy <= bounds.y + bounds.height then

                    -- Check if it's equipment (cannot be assigned to quickslots)
                    local is_equipment = item_obj.equipment_slot or item_obj.item_type == "equipment"

                    if is_equipment then
                        -- Equipment cannot be assigned to quickslots
                        helpers.play_sound("ui", "error")
                        -- Don't mark as placed, will return to original position
                    elseif item_obj.use and item_obj.canUse then
                        -- Only consumable items can be placed in quickslots
                        -- Place item back to grid first
                        self.inventory:placeItem(
                            item_id,
                            item_obj,
                            self.drag_state.origin_x,
                            self.drag_state.origin_y,
                            self.drag_state.origin_width,
                            self.drag_state.origin_height,
                            self.drag_state.origin_rotated
                        )

                        -- If dragged from another quickslot, remove from that slot first
                        if self.drag_state.from_quickslot_index and self.drag_state.from_quickslot_index ~= slot_index then
                            self.inventory:removeQuickslot(self.drag_state.from_quickslot_index)
                        end

                        -- Assign to quickslot
                        local success, message = self.inventory:assignQuickslot(slot_index, item_id)
                        if success then
                            helpers.play_sound("ui", "select")
                            placed = true
                        else
                            helpers.play_sound("ui", "error")
                            placed = true  -- Item is already back in grid
                        end
                    else
                        -- Non-usable items
                        helpers.play_sound("ui", "error")
                        -- Don't mark as placed, will return to original position
                    end
                    break
                end
            end
        end

        -- If not placed in equipment slot or quickslot, try grid placement
        if not placed then
            -- Adjust for offset to get top-left corner of item
            local item_top_left_x = vx - self.drag_state.offset_x
            local item_top_left_y = vy - self.drag_state.offset_y

            -- Calculate item size for center-based placement
            local CELL_SIZE, CELL_SPACING = slot_renderer.getGridConstants()

            -- For natural drag & drop, use first cell's center (not the entire item's center)
            -- This prevents multi-cell items from "sinking down" due to their center being in the next cell
            local snap_point_x = item_top_left_x + CELL_SIZE / 2
            local snap_point_y = item_top_left_y + CELL_SIZE / 2

            local drop_grid_x, drop_grid_y = slot_renderer.screenToGrid(snap_point_x, snap_point_y, self.grid_start_x, self.grid_start_y)

            -- Check if we can place at drop position
            if item_obj and self.inventory:canPlaceItem(drop_grid_x, drop_grid_y, self.drag_state.origin_width, self.drag_state.origin_height) then
                -- Place at new position
                self.inventory:placeItem(
                    item_id,
                    item_obj,
                    drop_grid_x,
                    drop_grid_y,
                    self.drag_state.origin_width,
                    self.drag_state.origin_height,
                    self.drag_state.origin_rotated
                )
                helpers.play_sound("ui", "select")
                placed = true
            end
        end

        -- If still not placed, restore to original position
        if not placed then
            if item_obj then
                self.inventory:placeItem(
                    item_id,
                    item_obj,
                    self.drag_state.origin_x,
                    self.drag_state.origin_y,
                    self.drag_state.origin_width,
                    self.drag_state.origin_height,
                    self.drag_state.origin_rotated
                )
            end
            helpers.play_sound("ui", "error")
        end

        -- End drag
        self.drag_state.active = false
        self.drag_state.item_id = nil
        self.drag_state.from_quickslot_index = nil  -- Reset quickslot source
    elseif button == 2 and self.quickslot_hold.active then
        -- Right-click release: check if hold duration was met
        if self.quickslot_hold.timer >= self.quickslot_hold.duration then
            -- Hold duration reached, remove item from quickslot
            local slot_index = self.quickslot_hold.slot_index
            if slot_index and self.inventory.quickslots[slot_index] then
                self.inventory:removeQuickslot(slot_index)
                helpers.play_sound("ui", "select")
            end
        end

        -- Reset hold state
        self.quickslot_hold.active = false
        self.quickslot_hold.slot_index = nil
        self.quickslot_hold.timer = 0
        self.quickslot_hold.source = nil
    end
end

-- Handle mouse movement (disable cursor mode when mouse moves)
function mouse_input.mousemoved(self, x, y, dx, dy)
    -- Disable cursor mode when mouse moves
    if dx ~= 0 or dy ~= 0 then
        self.cursor_mode = false
    end
end

return mouse_input

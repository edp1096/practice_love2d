-- engine/ui/screens/inventory/input.lua
-- Handles all input for the grid-based inventory UI

local input_handler = {}

local display = require "engine.core.display"
local input = require "engine.core.input"
local sound = require "engine.core.sound"
local coords = require "engine.core.coords"
local slot_renderer = require "engine.ui.screens.inventory.inventory_renderer"

-- Equipment slot layout (2x4 grid)
local EQUIPMENT_LAYOUT = {
    {name = "helmet", x = 0, y = 0},
    {name = "weapon", x = 1, y = 0},
    {name = "chest", x = 0, y = 1},
    {name = "shield", x = 1, y = 1},
    {name = "gloves", x = 0, y = 2},
    {name = "boots", x = 1, y = 2},
    {name = "bracelet", x = 0, y = 3},
    {name = "ring", x = 1, y = 3}
}

-- Get equipment slot name from cursor position
local function getEquipmentSlotName(cursor_x, cursor_y)
    for _, slot_info in ipairs(EQUIPMENT_LAYOUT) do
        if slot_info.x == cursor_x and slot_info.y == cursor_y then
            return slot_info.name
        end
    end
    return nil
end

-- Safe sound wrapper
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

-- Handle keyboard input
function input_handler.keypressed(self, key)
    -- Handle debug keys first
    local debug = require "engine.core.debug"
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process inventory keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if input:wasPressed("open_inventory", "keyboard", key) or input:wasPressed("menu_back", "keyboard", key) or input:wasPressed("pause", "keyboard", key) then
        -- I key, menu_back, or pause to close (toggle behavior)
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif input:wasPressed("menu_left", "keyboard", key) or input:wasPressed("menu_right", "keyboard", key) then
        -- Navigate between items
        input_handler.moveSelection(self)
    elseif input:wasPressed("menu_select", "keyboard", key) then
        input_handler.useSelectedItem(self)
    elseif input:wasPressed("use_item", "keyboard", key) then
        -- Use item (Q key by default, configurable via input_config)
        input_handler.useSelectedItem(self)
    elseif tonumber(key) then
        local slot_num = tonumber(key)
        -- Number keys 1-9: quick select items by grid position
        input_handler.selectItemByNumber(self, slot_num)
    end
end

-- Handle gamepad input
function input_handler.gamepadpressed(self, joystick, button)
    -- Direction pad: Move cursor (1 step at a time, with equipment/quickslot mode support)
    if input:wasPressed("menu_up", "gamepad", button) then
        self.cursor_mode = true
        if self.quickslot_mode then
            -- Exit quickslot mode, return to grid bottom
            self.quickslot_mode = false
            self.cursor_y = self.inventory.grid_height
        elseif self.equipment_mode then
            self.equipment_cursor_y = (self.equipment_cursor_y - 1 + 4) % 4
        else
            self.cursor_y = self.cursor_y == 1 and self.inventory.grid_height or self.cursor_y - 1
        end
        play_sound("ui", "move")
        return
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.cursor_mode = true
        if self.quickslot_mode then
            -- In quickslot mode, down does nothing
        elseif self.equipment_mode then
            self.equipment_cursor_y = (self.equipment_cursor_y + 1) % 4
        else
            -- In grid mode
            if self.cursor_y == self.inventory.grid_height then
                -- At bottom of grid, enter quickslot mode
                self.quickslot_mode = true
            else
                self.cursor_y = self.cursor_y + 1
            end
        end
        play_sound("ui", "move")
        return
    elseif input:wasPressed("menu_left", "gamepad", button) then
        self.cursor_mode = true
        if self.quickslot_mode then
            -- Move left in quickslots (wrap around)
            self.quickslot_cursor = self.quickslot_cursor == 1 and 5 or self.quickslot_cursor - 1
        elseif self.equipment_mode then
            -- Toggle equipment X (0 <-> 1)
            self.equipment_cursor_x = (self.equipment_cursor_x == 0) and 1 or 0
        else
            if self.cursor_x == 1 then
                -- Switch to equipment mode
                self.equipment_mode = true
                self.equipment_cursor_x = 1
            else
                self.cursor_x = self.cursor_x - 1
            end
        end
        play_sound("ui", "move")
        return
    elseif input:wasPressed("menu_right", "gamepad", button) then
        self.cursor_mode = true
        if self.quickslot_mode then
            -- Move right in quickslots (wrap around)
            self.quickslot_cursor = self.quickslot_cursor == 5 and 1 or self.quickslot_cursor + 1
        elseif self.equipment_mode then
            -- Switch to grid mode
            self.equipment_mode = false
            self.cursor_x = 1
        else
            self.cursor_x = self.cursor_x == self.inventory.grid_width and 1 or self.cursor_x + 1
        end
        play_sound("ui", "move")
        return
    end

    -- A button: Pickup/Drop/Equip/Assign item (toggle)
    if input:wasPressed("menu_select", "gamepad", button) or input:wasPressed("attack", "gamepad", button) then
        if self.gamepad_drag.active then
            -- Drop/Equip/Assign item at cursor
            if self.quickslot_mode then
                input_handler.gamepadAssignToQuickslot(self)
            elseif self.equipment_mode then
                input_handler.gamepadEquipToSlot(self)
            else
                input_handler.gamepadDropItem(self)
            end
        else
            -- Pickup item at cursor
            if self.quickslot_mode then
                input_handler.gamepadPickupFromQuickslot(self)
            elseif self.equipment_mode then
                input_handler.gamepadPickupFromEquipment(self)
            else
                input_handler.gamepadPickupItem(self)
            end
        end
        return
    end

    -- X button: Rotate item at cursor OR hold to remove from quickslot
    if input:wasPressed("parry", "gamepad", button) then
        if self.quickslot_mode and not self.gamepad_drag.active then
            -- Start hold timer to remove item from quickslot
            local slot_index = self.quickslot_cursor
            local item_id = self.inventory.quickslots[slot_index]
            if item_id then
                self.quickslot_hold.active = true
                self.quickslot_hold.slot_index = slot_index
                self.quickslot_hold.timer = 0
            end
        elseif self.gamepad_drag.active then
            -- Rotate item being held
            local item_id = self.gamepad_drag.item_id
            local item_data = {
                item = self.gamepad_drag.item_obj,
                x = self.cursor_x,
                y = self.cursor_y,
                width = self.gamepad_drag.origin_width,
                height = self.gamepad_drag.origin_height,
                rotated = self.gamepad_drag.origin_rotated
            }

            -- Swap width/height for rotation check
            local new_width = item_data.height
            local new_height = item_data.width

            if new_width ~= new_height then
                self.gamepad_drag.origin_width = new_width
                self.gamepad_drag.origin_height = new_height
                self.gamepad_drag.origin_rotated = not self.gamepad_drag.origin_rotated
                play_sound("ui", "select")
            else
                play_sound("ui", "error")
            end
        else
            -- Rotate item at cursor
            local item_id = self.inventory.grid[self.cursor_y][self.cursor_x]
            if item_id then
                if self.inventory:rotateItem(item_id) then
                    play_sound("ui", "select")
                else
                    play_sound("ui", "error")
                end
            end
        end
        return
    end

    -- Y button or B button: Use selected item
    if input:wasPressed("interact", "gamepad", button) or input:wasPressed("jump", "gamepad", button) then
        -- Auto-select item at cursor
        local item_id = self.inventory.grid[self.cursor_y][self.cursor_x]
        if item_id then
            self.selected_item_id = item_id
            self.inventory.selected_item_id = item_id
        end

        input_handler.useSelectedItem(self)
        return
    end

    -- L1/LB button: Toggle between grid and quickslot mode (quick navigation)
    if button == "leftshoulder" then
        self.cursor_mode = true
        if self.quickslot_mode then
            -- Exit quickslot mode, return to grid (last cursor position)
            self.quickslot_mode = false
            -- Cursor position already preserved
        elseif self.equipment_mode then
            -- Exit equipment mode, enter quickslot mode
            self.equipment_mode = false
            self.quickslot_mode = true
        else
            -- Exit grid mode, enter quickslot mode
            self.quickslot_mode = true
        end
        play_sound("ui", "move")
        return
    end

    -- Back or Start: Close inventory
    if input:wasPressed("menu_back", "gamepad", button) or input:wasPressed("pause", "gamepad", button) then
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
        return
    end

    -- "open_inventory" action to close inventory (toggle behavior)
    if input:wasPressed("open_inventory", "gamepad", button) then
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
        return
    end
end

-- Handle gamepad axis (for Xbox controller triggers)
function input_handler.gamepadaxis(self, joystick, axis, value)
    -- Use input coordinator to handle trigger-to-button conversion
    local input_sys = require "engine.core.input"
    local action = input_sys:handleGamepadAxis(joystick, axis, value)

    if action == "open_inventory" then
        -- "open_inventory" trigger pressed - close inventory (toggle behavior)
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif action == "next_item" then
        -- "next_item" trigger pressed - move selection
        input_handler.moveSelection(self)
    end
end

-- Handle mouse input
function input_handler.mousepressed(self, x, y, button)
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

                                    play_sound("ui", "select")
                                    return
                                else
                                    print("Unequip failed:", err)
                                    play_sound("ui", "error")
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

                play_sound("ui", "select")
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

                            play_sound("ui", "select")
                            return
                        end
                    end
                    break
                end
            end
        end

        -- Not dragging, handle as normal click
        input_handler.handleClick(self, x, y)
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
                    play_sound("ui", "select")  -- Rotation success
                else
                    play_sound("ui", "error")  -- Rotation failed (1x1 or no space)
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
                    end
                    return
                end
            end
        end

        -- No item clicked, use selected item
        input_handler.useSelectedItem(self)
    end
end

-- Handle mouse release (drop)
function input_handler.mousereleased(self, x, y, button)
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
                            play_sound("ui", "select")
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
                        print("[Quickslot] Equipment cannot be assigned to quickslots")
                        play_sound("ui", "error")
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
                            play_sound("ui", "select")
                            placed = true
                        else
                            print("[Quickslot] " .. (message or "Cannot assign"))
                            play_sound("ui", "error")
                            placed = true  -- Item is already back in grid
                        end
                    else
                        -- Non-usable items
                        print("[Quickslot] Only consumable items can be assigned to quickslots")
                        play_sound("ui", "error")
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
                play_sound("ui", "select")
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
            play_sound("ui", "error")
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
                play_sound("ui", "select")
            end
        end

        -- Reset hold state
        self.quickslot_hold.active = false
        self.quickslot_hold.slot_index = nil
        self.quickslot_hold.timer = 0
    end
end

-- Handle mouse movement (disable cursor mode when mouse moves)
function input_handler.mousemoved(self, x, y, dx, dy)
    -- Disable cursor mode when mouse moves
    if dx ~= 0 or dy ~= 0 then
        self.cursor_mode = false
    end
end

-- Handle touch input
function input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
    -- Check if touch is in virtual gamepad area FIRST
    local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        if virtual_gamepad and virtual_gamepad:isInVirtualPadArea(x, y) then
            -- Let virtual gamepad handle it
            -- Return false immediately without processing the touch
            return false
        end
    end

    -- Handle touch as mouse press (start drag)
    input_handler.mousepressed(self, x, y, 1)
    -- Block other handlers
    return true
end

-- Handle touch release (same as mouse release)
function input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
    -- Check if touch is in virtual gamepad area
    local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        if virtual_gamepad and virtual_gamepad:isInVirtualPadArea(x, y) then
            return false
        end
    end

    -- Handle touch as mouse release (drop)
    input_handler.mousereleased(self, x, y, 1)
    return true
end

-- Handle click/touch on UI elements
function input_handler.handleClick(self, x, y)
    -- Convert screen coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Check if clicked on close button
    if self.close_button_bounds then
        local cb = self.close_button_bounds
        if vx >= cb.x and vx <= cb.x + cb.size and
            vy >= cb.y and vy <= cb.y + cb.size then
            local scene_control = require "engine.core.scene_control"
            scene_control.pop()
            return
        end
    end

    -- Convert virtual coords to grid coordinates
    local grid_x, grid_y = slot_renderer.screenToGrid(vx, vy, self.grid_start_x, self.grid_start_y)

    -- Check if click is within grid bounds
    if grid_x >= 1 and grid_x <= self.inventory.grid_width and
       grid_y >= 1 and grid_y <= self.inventory.grid_height then

        -- Get item at clicked grid position
        local item_id = self.inventory.grid[grid_y][grid_x]

        if item_id then
            -- Select the item
            self.selected_item_id = item_id
            self.inventory.selected_item_id = item_id
            play_sound("ui", "select")
        end
    end
end

-- Move selection to next item (for keyboard/gamepad navigation)
function input_handler.moveSelection(self)
    self.inventory:selectNext()
    self.selected_item_id = self.inventory.selected_item_id
    play_sound("ui", "select")
end

-- Gamepad pickup item at cursor
function input_handler.gamepadPickupItem(self)
    local item_id = self.inventory.grid[self.cursor_y][self.cursor_x]
    if not item_id then
        play_sound("ui", "error")
        return false
    end

    local item_data = self.inventory.items[item_id]
    if not item_data then
        play_sound("ui", "error")
        return false
    end

    -- Start gamepad drag
    self.gamepad_drag.active = true
    self.gamepad_drag.item_id = item_id
    self.gamepad_drag.item_obj = item_data.item
    self.gamepad_drag.origin_x = item_data.x
    self.gamepad_drag.origin_y = item_data.y
    self.gamepad_drag.origin_width = item_data.width
    self.gamepad_drag.origin_height = item_data.height
    self.gamepad_drag.origin_rotated = item_data.rotated

    -- Remove from grid temporarily
    self.inventory:removeItem(item_id)

    play_sound("ui", "select")
    return true
end

-- Gamepad drop item at cursor
function input_handler.gamepadDropItem(self)
    if not self.gamepad_drag.active then
        return false
    end

    local item_id = self.gamepad_drag.item_id
    local item_obj = self.gamepad_drag.item_obj
    local drop_x = self.cursor_x
    local drop_y = self.cursor_y

    -- Check if we can place at cursor position
    if item_obj and self.inventory:canPlaceItem(drop_x, drop_y, self.gamepad_drag.origin_width, self.gamepad_drag.origin_height) then
        -- Place at cursor position
        self.inventory:placeItem(
            item_id,
            item_obj,
            drop_x,
            drop_y,
            self.gamepad_drag.origin_width,
            self.gamepad_drag.origin_height,
            self.gamepad_drag.origin_rotated
        )
        play_sound("ui", "select")
    else
        -- Restore to original position
        if item_obj then
            self.inventory:placeItem(
                item_id,
                item_obj,
                self.gamepad_drag.origin_x,
                self.gamepad_drag.origin_y,
                self.gamepad_drag.origin_width,
                self.gamepad_drag.origin_height,
                self.gamepad_drag.origin_rotated
            )
        end
        play_sound("ui", "error")
    end

    -- End gamepad drag
    self.gamepad_drag.active = false
    self.gamepad_drag.item_id = nil
    return true
end

-- Gamepad pickup item from equipment slot
function input_handler.gamepadPickupFromEquipment(self)
    -- Get slot name from cursor position
    local slot_name = getEquipmentSlotName(self.equipment_cursor_x, self.equipment_cursor_y)
    if not slot_name then
        play_sound("ui", "error")
        return false
    end

    -- Check if slot has an item
    local item_id = self.inventory.equipment_slots[slot_name]
    if not item_id then
        play_sound("ui", "error")
        return false
    end

    -- Unequip item (moves to grid)
    local success, err = self.inventory:unequipItem(slot_name, self.player)
    if not success then
        print("Unequip failed:", err)
        play_sound("ui", "error")
        return false
    end

    -- Item is now in grid, get its data
    local item_data = self.inventory.items[item_id]
    if not item_data then
        play_sound("ui", "error")
        return false
    end

    -- Start gamepad drag
    self.gamepad_drag.active = true
    self.gamepad_drag.item_id = item_id
    self.gamepad_drag.item_obj = item_data.item
    self.gamepad_drag.origin_x = item_data.x
    self.gamepad_drag.origin_y = item_data.y
    self.gamepad_drag.origin_width = item_data.width
    self.gamepad_drag.origin_height = item_data.height
    self.gamepad_drag.origin_rotated = item_data.rotated

    -- Remove from grid (holding in hand)
    self.inventory:removeItem(item_id)

    play_sound("ui", "select")
    return true
end

-- Gamepad equip item to equipment slot
function input_handler.gamepadEquipToSlot(self)
    if not self.gamepad_drag.active then
        return false
    end

    local item_id = self.gamepad_drag.item_id
    local item_obj = self.gamepad_drag.item_obj

    -- Get slot name from cursor position
    local slot_name = getEquipmentSlotName(self.equipment_cursor_x, self.equipment_cursor_y)
    if not slot_name then
        play_sound("ui", "error")
        return false
    end

    -- IMPORTANT: Place item back to grid first (equipItem needs item to exist)
    self.inventory:placeItem(
        item_id,
        item_obj,
        self.gamepad_drag.origin_x,
        self.gamepad_drag.origin_y,
        self.gamepad_drag.origin_width,
        self.gamepad_drag.origin_height,
        self.gamepad_drag.origin_rotated
    )

    -- Try to equip to this slot
    local success, err = self.inventory:equipItem(item_id, slot_name, self.player)
    if success then
        play_sound("ui", "select")
    else
        -- Equip failed, but item is already back in grid
        print("Equip failed:", err)
        play_sound("ui", "error")
    end

    -- End gamepad drag
    self.gamepad_drag.active = false
    self.gamepad_drag.item_id = nil
    return true
end

-- Move cursor to next item in direction (for gamepad cursor navigation)
function input_handler.moveCursorToNextItem(self, direction)
    local dx, dy = 0, 0
    if direction == "up" then dy = -1
    elseif direction == "down" then dy = 1
    elseif direction == "left" then dx = -1
    elseif direction == "right" then dx = 1
    end

    -- Find next item in direction
    local start_x, start_y = self.cursor_x, self.cursor_y
    local max_steps = math.max(self.inventory.grid_width, self.inventory.grid_height)

    for step = 1, max_steps do
        local new_x = start_x + dx * step
        local new_y = start_y + dy * step

        -- Check boundaries
        if new_x < 1 or new_x > self.inventory.grid_width or
           new_y < 1 or new_y > self.inventory.grid_height then
            break
        end

        -- Check if there's an item at this position
        local item_id = self.inventory.grid[new_y][new_x]
        if item_id then
            -- Found an item, get its top-left corner
            local item_data = self.inventory.items[item_id]
            if item_data then
                self.cursor_x = item_data.x
                self.cursor_y = item_data.y
                play_sound("ui", "move")
                return
            end
        end
    end

    -- No item found, just move one step
    self.cursor_x = math.max(1, math.min(self.inventory.grid_width, start_x + dx))
    self.cursor_y = math.max(1, math.min(self.inventory.grid_height, start_y + dy))
    play_sound("ui", "move")
end

-- Select item by number (1-9 quick select)
function input_handler.selectItemByNumber(self, slot_num)
    -- Get sorted list of item IDs
    local item_ids = {}
    for item_id, _ in pairs(self.inventory.items) do
        table.insert(item_ids, item_id)
    end

    -- Sort by grid position (top-left to bottom-right)
    table.sort(item_ids, function(a, b)
        local item_a = self.inventory.items[a]
        local item_b = self.inventory.items[b]
        if item_a.y == item_b.y then
            return item_a.x < item_b.x
        end
        return item_a.y < item_b.y
    end)

    if slot_num >= 1 and slot_num <= #item_ids then
        self.selected_item_id = item_ids[slot_num]
        self.inventory.selected_item_id = item_ids[slot_num]
        play_sound("ui", "select")
    end
end

-- Use the currently selected item
function input_handler.useSelectedItem(self)
    if self.inventory:useSelectedItem(self.player) then
        play_sound("ui", "use")

        -- Update selection if item was removed
        self.selected_item_id = self.inventory.selected_item_id
    else
        play_sound("ui", "error")
    end
end

-- Gamepad assign item to quickslot
function input_handler.gamepadAssignToQuickslot(self)
    if not self.gamepad_drag.active then
        return false
    end

    local item_id = self.gamepad_drag.item_id
    local item_obj = self.gamepad_drag.item_obj
    local slot_index = self.quickslot_cursor

    -- Check if it's equipment (cannot be assigned)
    local is_equipment = item_obj.equipment_slot or item_obj.item_type == "equipment"

    if is_equipment then
        print("[Quickslot] Equipment cannot be assigned to quickslots")
        play_sound("ui", "error")

        -- Restore to original position
        self.inventory:placeItem(
            item_id,
            item_obj,
            self.gamepad_drag.origin_x,
            self.gamepad_drag.origin_y,
            self.gamepad_drag.origin_width,
            self.gamepad_drag.origin_height,
            self.gamepad_drag.origin_rotated
        )
    elseif item_obj.use and item_obj.canUse then
        -- Place item back to grid first
        self.inventory:placeItem(
            item_id,
            item_obj,
            self.gamepad_drag.origin_x,
            self.gamepad_drag.origin_y,
            self.gamepad_drag.origin_width,
            self.gamepad_drag.origin_height,
            self.gamepad_drag.origin_rotated
        )

        -- Assign to quickslot
        local success, message = self.inventory:assignQuickslot(slot_index, item_id)
        if success then
            play_sound("ui", "select")
        else
            print("[Quickslot] " .. (message or "Cannot assign"))
            play_sound("ui", "error")
        end
    else
        print("[Quickslot] Only consumable items can be assigned to quickslots")
        play_sound("ui", "error")

        -- Restore to original position
        self.inventory:placeItem(
            item_id,
            item_obj,
            self.gamepad_drag.origin_x,
            self.gamepad_drag.origin_y,
            self.gamepad_drag.origin_width,
            self.gamepad_drag.origin_height,
            self.gamepad_drag.origin_rotated
        )
    end

    -- End gamepad drag
    self.gamepad_drag.active = false
    self.gamepad_drag.item_id = nil
    return true
end

-- Gamepad pickup item from quickslot
function input_handler.gamepadPickupFromQuickslot(self)
    local slot_index = self.quickslot_cursor
    local item_id = self.inventory.quickslots[slot_index]

    if not item_id then
        play_sound("ui", "error")
        return false
    end

    local item_data = self.inventory.items[item_id]
    if not item_data then
        play_sound("ui", "error")
        return false
    end

    -- Start gamepad drag
    self.gamepad_drag.active = true
    self.gamepad_drag.item_id = item_id
    self.gamepad_drag.item_obj = item_data.item
    self.gamepad_drag.origin_x = item_data.x
    self.gamepad_drag.origin_y = item_data.y
    self.gamepad_drag.origin_width = item_data.width
    self.gamepad_drag.origin_height = item_data.height
    self.gamepad_drag.origin_rotated = item_data.rotated

    -- Remove from grid temporarily (keep quickslot assignment)
    self.inventory:removeItem(item_id)

    play_sound("ui", "select")
    return true
end

return input_handler

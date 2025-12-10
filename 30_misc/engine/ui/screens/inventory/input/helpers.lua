-- engine/ui/screens/inventory/input/helpers.lua
-- Shared helper functions for inventory input handling

local helpers = {}

local coords = require "engine.core.coords"
local display = require "engine.core.display"
local sound_utils = require "engine.utils.sound_utils"
local slot_renderer = require "engine.ui.screens.inventory.inventory_renderer"

-- Equipment slot layout (2x4 grid)
helpers.EQUIPMENT_LAYOUT = {
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
function helpers.getEquipmentSlotName(cursor_x, cursor_y)
    for _, slot_info in ipairs(helpers.EQUIPMENT_LAYOUT) do
        if slot_info.x == cursor_x and slot_info.y == cursor_y then
            return slot_info.name
        end
    end
    return nil
end

-- Use shared sound utility
helpers.play_sound = sound_utils.play

-- Handle click/touch on UI elements
function helpers.handleClick(self, x, y)
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
            helpers.play_sound("ui", "select")
        end
    end
end

-- Move selection to next item (for keyboard/gamepad navigation)
function helpers.moveSelection(self)
    self.inventory:selectNext()
    self.selected_item_id = self.inventory.selected_item_id
    helpers.play_sound("ui", "select")
end

-- Gamepad pickup item at cursor
function helpers.gamepadPickupItem(self)
    local item_id = self.inventory.grid[self.cursor_y][self.cursor_x]
    if not item_id then
        helpers.play_sound("ui", "error")
        return false
    end

    local item_data = self.inventory.items[item_id]
    if not item_data then
        helpers.play_sound("ui", "error")
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

    helpers.play_sound("ui", "select")
    return true
end

-- Gamepad drop item at cursor
function helpers.gamepadDropItem(self)
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
        helpers.play_sound("ui", "select")
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
        helpers.play_sound("ui", "error")
    end

    -- End gamepad drag
    self.gamepad_drag.active = false
    self.gamepad_drag.item_id = nil
    return true
end

-- Gamepad pickup item from equipment slot
function helpers.gamepadPickupFromEquipment(self)
    -- Get slot name from cursor position
    local slot_name = helpers.getEquipmentSlotName(self.equipment_cursor_x, self.equipment_cursor_y)
    if not slot_name then
        helpers.play_sound("ui", "error")
        return false
    end

    -- Check if slot has an item
    local item_id = self.inventory.equipment_slots[slot_name]
    if not item_id then
        helpers.play_sound("ui", "error")
        return false
    end

    -- Unequip item (moves to grid)
    local success, err = self.inventory:unequipItem(slot_name, self.player)
    if not success then
        helpers.play_sound("ui", "error")
        return false
    end

    -- Item is now in grid, get its data
    local item_data = self.inventory.items[item_id]
    if not item_data then
        helpers.play_sound("ui", "error")
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

    helpers.play_sound("ui", "select")
    return true
end

-- Gamepad equip item to equipment slot
function helpers.gamepadEquipToSlot(self)
    if not self.gamepad_drag.active then
        return false
    end

    local item_id = self.gamepad_drag.item_id
    local item_obj = self.gamepad_drag.item_obj

    -- Get slot name from cursor position
    local slot_name = helpers.getEquipmentSlotName(self.equipment_cursor_x, self.equipment_cursor_y)
    if not slot_name then
        helpers.play_sound("ui", "error")
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
        helpers.play_sound("ui", "select")
    else
        -- Equip failed, but item is already back in grid
        helpers.play_sound("ui", "error")
    end

    -- End gamepad drag
    self.gamepad_drag.active = false
    self.gamepad_drag.item_id = nil
    return true
end

-- Move cursor to next item in direction (for gamepad cursor navigation)
function helpers.moveCursorToNextItem(self, direction)
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
                helpers.play_sound("ui", "move")
                return
            end
        end
    end

    -- No item found, just move one step
    self.cursor_x = math.max(1, math.min(self.inventory.grid_width, start_x + dx))
    self.cursor_y = math.max(1, math.min(self.inventory.grid_height, start_y + dy))
    helpers.play_sound("ui", "move")
end

-- Select item by number (1-9 quick select)
function helpers.selectItemByNumber(self, slot_num)
    -- Get sorted list of item IDs
    local item_ids = {}
    for item_id, _ in pairs(self.inventory.items) do
        table.insert(item_ids, item_id)
    end

    -- Sort by grid position (top-left to bottom-right)
    table.sort(item_ids, function(a, b)
        local item_a = self.inventory.items[a]
        local item_b = self.inventory.items[b]
        if not item_a then return false end
        if not item_b then return true end
        if item_a.y == item_b.y then
            return item_a.x < item_b.x
        end
        return item_a.y < item_b.y
    end)

    if slot_num >= 1 and slot_num <= #item_ids then
        self.selected_item_id = item_ids[slot_num]
        self.inventory.selected_item_id = item_ids[slot_num]
        helpers.play_sound("ui", "select")
    end
end

-- Use the currently selected item
function helpers.useSelectedItem(self)
    if self.inventory:useSelectedItem(self.player) then
        helpers.play_sound("ui", "use")

        -- Update selection if item was removed
        self.selected_item_id = self.inventory.selected_item_id
    else
        helpers.play_sound("ui", "error")
    end
end

-- Gamepad assign item to quickslot
function helpers.gamepadAssignToQuickslot(self)
    if not self.gamepad_drag.active then
        return false
    end

    local item_id = self.gamepad_drag.item_id
    local item_obj = self.gamepad_drag.item_obj
    local slot_index = self.quickslot_cursor

    -- Check if it's equipment (cannot be assigned)
    local is_equipment = item_obj.equipment_slot or item_obj.item_type == "equipment"

    if is_equipment then
        helpers.play_sound("ui", "error")

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
            helpers.play_sound("ui", "select")
        else
            helpers.play_sound("ui", "error")
        end
    else
        helpers.play_sound("ui", "error")

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
function helpers.gamepadPickupFromQuickslot(self)
    local slot_index = self.quickslot_cursor
    local item_id = self.inventory.quickslots[slot_index]

    if not item_id then
        helpers.play_sound("ui", "error")
        return false
    end

    local item_data = self.inventory.items[item_id]
    if not item_data then
        helpers.play_sound("ui", "error")
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

    helpers.play_sound("ui", "select")
    return true
end

return helpers

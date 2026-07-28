-- engine/ui/screens/inventory/input/gamepad.lua
-- Gamepad input handling for inventory

local gamepad_input = {}

local input = require "engine.core.input"

-- Handle gamepad input
function gamepad_input.gamepadpressed(self, joystick, button, helpers)
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
        helpers.play_sound("ui", "move")
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
        helpers.play_sound("ui", "move")
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
        helpers.play_sound("ui", "move")
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
        helpers.play_sound("ui", "move")
        return
    end

    -- A button: Pickup/Drop/Equip/Assign item (toggle)
    if input:wasPressed("menu_select", "gamepad", button) or input:wasPressed("attack", "gamepad", button) then
        if self.gamepad_drag.active then
            -- Drop/Equip/Assign item at cursor
            if self.quickslot_mode then
                helpers.gamepadAssignToQuickslot(self)
            elseif self.equipment_mode then
                helpers.gamepadEquipToSlot(self)
            else
                helpers.gamepadDropItem(self)
            end
        else
            -- Pickup item at cursor
            if self.quickslot_mode then
                helpers.gamepadPickupFromQuickslot(self)
            elseif self.equipment_mode then
                helpers.gamepadPickupFromEquipment(self)
            else
                helpers.gamepadPickupItem(self)
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
                self.quickslot_hold.source = "gamepad"
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
                helpers.play_sound("ui", "select")
            else
                helpers.play_sound("ui", "error")
            end
        else
            -- Rotate item at cursor
            local item_id = self.inventory.grid[self.cursor_y][self.cursor_x]
            if item_id then
                if self.inventory:rotateItem(item_id) then
                    helpers.play_sound("ui", "select")
                else
                    helpers.play_sound("ui", "error")
                end
            end
        end
        return
    end

    -- Y button or B button: Use selected item (double-press logic)
    if input:wasPressed("interact", "gamepad", button) or input:wasPressed("jump", "gamepad", button) then
        -- Auto-select item at cursor
        local item_id = self.inventory.grid[self.cursor_y][self.cursor_x]
        if item_id then
            self.selected_item_id = item_id
            self.inventory.selected_item_id = item_id

            -- Double-press logic: First press selects, second press uses
            if not self.last_selected_item_for_use or self.last_selected_item_for_use ~= item_id then
                -- First press or different item - just select
                self.last_selected_item_for_use = item_id
                helpers.play_sound("ui", "select")
            else
                -- Second press on same item - use it
                helpers.useSelectedItem(self)
                self.last_selected_item_for_use = nil  -- Reset after use
            end
        else
            -- No item at cursor - reset double-press state
            self.last_selected_item_for_use = nil
        end
        return
    end

    -- L1/LB button: Toggle between grid and quickslot mode (quick navigation)
    local input = require "engine.core.input"
    if input:wasPressed("toggle_cursor_mode", "gamepad", button) then
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
        helpers.play_sound("ui", "move")
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
function gamepad_input.gamepadaxis(self, joystick, axis, value)
    -- Use input coordinator to handle trigger-to-button conversion
    local input_sys = require "engine.core.input"
    local action = input_sys:handleGamepadAxis(joystick, axis, value)

    if action == "open_inventory" then
        -- "open_inventory" trigger pressed - close inventory (toggle behavior)
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif action == "next_item" then
        -- "next_item" trigger pressed - move selection
        local helpers = require "engine.ui.screens.inventory.input.helpers"
        helpers.moveSelection(self)
    end
end

return gamepad_input

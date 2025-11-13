-- systems/inventory.lua
-- Grid-based inventory management system

local inventory = {}
inventory.__index = inventory
inventory.item_class = nil  -- Injected item class

function inventory:new(item_class)
    local instance = setmetatable({}, inventory)

    instance.item_class = item_class or self.item_class

    -- Grid configuration
    instance.grid_width = 10
    instance.grid_height = 6  -- 10x6 grid (60 cells total)

    -- Grid storage: 2D array [y][x] = item_uuid or nil
    instance.grid = {}
    for y = 1, instance.grid_height do
        instance.grid[y] = {}
        for x = 1, instance.grid_width do
            instance.grid[y][x] = nil
        end
    end

    -- Item instances: map of uuid -> item data
    instance.items = {}  -- { [uuid] = {item=item_obj, x=1, y=1, width=1, height=1, rotated=false}, ... }

    -- Selected item (uuid instead of slot index)
    instance.selected_item_id = nil

    -- Equipment slots: specialized slots for wearable items
    instance.equipment_slots = {
        helmet = nil,   -- Head armor
        chest = nil,    -- Body armor
        weapon = nil,   -- Main weapon
        shield = nil,   -- Off-hand shield
        bracelet = nil, -- Bracelet
        ring = nil,     -- Ring
        boots = nil,    -- Footwear
        gloves = nil    -- Hand armor
    }

    -- Quickslots: hotbar for quick item usage (1-5 keys)
    instance.quickslots = {
        nil,  -- Slot 1
        nil,  -- Slot 2
        nil,  -- Slot 3
        nil,  -- Slot 4
        nil   -- Slot 5
    }

    -- Legacy compatibility
    instance.max_slots = 60  -- 10x6 grid
    instance.selected_slot = 1  -- For backward compatibility

    return instance
end

-- ============================================================================
-- Grid Management Functions
-- ============================================================================

-- Check if item can be placed at position (x, y) with given size
function inventory:canPlaceItem(x, y, width, height, ignore_uuid)
    -- Boundary check
    if x < 1 or y < 1 or x + width - 1 > self.grid_width or y + height - 1 > self.grid_height then
        return false
    end

    -- Collision check (all cells must be empty or belong to ignored item)
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            local cell_value = self.grid[y + dy][x + dx]
            if cell_value ~= nil and cell_value ~= ignore_uuid then
                return false  -- Cell is occupied
            end
        end
    end

    return true
end

-- Place item on grid at position (x, y)
function inventory:placeItem(item_id, item_obj, x, y, width, height, rotated)
    -- Mark all cells with item_id
    for dy = 0, height - 1 do
        for dx = 0, width - 1 do
            self.grid[y + dy][x + dx] = item_id
        end
    end

    -- Store item instance data
    self.items[item_id] = {
        item = item_obj,
        x = x,
        y = y,
        width = width,
        height = height,
        rotated = rotated or false
    }

    return true
end

-- Remove item from grid
function inventory:removeItem(item_id)
    local item_data = self.items[item_id]
    if not item_data then
        return false
    end

    -- Clear all grid cells
    for dy = 0, item_data.height - 1 do
        for dx = 0, item_data.width - 1 do
            if self.grid[item_data.y + dy] and self.grid[item_data.y + dy][item_data.x + dx] == item_id then
                self.grid[item_data.y + dy][item_data.x + dx] = nil
            end
        end
    end

    -- Remove item instance
    self.items[item_id] = nil

    -- Update selection if removed item was selected
    if self.selected_item_id == item_id then
        self.selected_item_id = nil
    end

    return true
end

-- Find empty space for item with given size
function inventory:findEmptySpace(width, height)
    -- Scan from top-left to find first available space
    for y = 1, self.grid_height - height + 1 do
        for x = 1, self.grid_width - width + 1 do
            if self:canPlaceItem(x, y, width, height) then
                return x, y
            end
        end
    end
    return nil, nil  -- No space available
end

-- Get item at grid position
function inventory:getItemAt(x, y)
    if x < 1 or x > self.grid_width or y < 1 or y > self.grid_height then
        return nil
    end

    local item_id = self.grid[y][x]
    if item_id then
        return item_id, self.items[item_id]
    end

    return nil, nil
end

-- ============================================================================
-- Public API Functions (High-level)
-- ============================================================================

-- Add item to inventory (auto-placement)
function inventory:addItem(item_type, quantity)
    quantity = quantity or 1

    -- Try to stack with existing item of same type
    for item_id, item_data in pairs(self.items) do
        local item = item_data.item
        if item.type == item_type and item.quantity < item.max_stack then
            local overflow = item:addQuantity(quantity)
            if overflow == 0 then
                return true  -- All added to existing stack
            else
                quantity = overflow  -- Continue with overflow
            end
        end
    end

    -- Create new item instance
    local new_item = self.item_class:new(item_type, quantity)
    local width = new_item.size.width
    local height = new_item.size.height

    -- Find space for new item
    local x, y = self:findEmptySpace(width, height)
    if x and y then
        self:placeItem(new_item.uuid, new_item, x, y, width, height, false)

        -- Auto-select first item if none selected
        if not self.selected_item_id then
            self.selected_item_id = new_item.uuid
        end

        return true, new_item.uuid  -- Return success and item ID
    else
        return false, nil  -- No space available
    end
end

-- Get currently selected item
function inventory:getSelectedItem()
    if not self.selected_item_id then
        return nil
    end

    local item_data = self.items[self.selected_item_id]
    if item_data then
        return item_data.item
    end

    return nil
end

-- Use selected item
function inventory:useSelectedItem(player)
    local item = self:getSelectedItem()
    if not item then
        return false
    end

    if not item:canUse(player) then
        return false
    end

    local success = item:use(player)
    if success then
        -- Remove item if quantity reaches 0
        if item.quantity <= 0 then
            self:removeItem(self.selected_item_id)
        end
        return true
    end

    return false
end

-- Select item by UUID
function inventory:selectItem(item_id)
    if self.items[item_id] then
        self.selected_item_id = item_id
        return true
    end
    return false
end

-- Select next item (for keyboard navigation)
function inventory:selectNext()
    local item_ids = {}
    for item_id, item_data in pairs(self.items) do
        -- Only include items in grid (not equipped items)
        if not item_data.equipped and item_data.x and item_data.y then
            table.insert(item_ids, item_id)
        end
    end

    if #item_ids == 0 then
        self.selected_item_id = nil
        return
    end

    -- Sort by grid position (top-left to bottom-right)
    table.sort(item_ids, function(a, b)
        local item_a = self.items[a]
        local item_b = self.items[b]
        if item_a.y == item_b.y then
            return item_a.x < item_b.x
        end
        return item_a.y < item_b.y
    end)

    -- Find current selection index
    local current_index = nil
    for i, item_id in ipairs(item_ids) do
        if item_id == self.selected_item_id then
            current_index = i
            break
        end
    end

    -- Select next item
    if current_index then
        local next_index = (current_index % #item_ids) + 1
        self.selected_item_id = item_ids[next_index]
    else
        self.selected_item_id = item_ids[1]
    end
end

-- Rotate item 90 degrees (swap width and height)
function inventory:rotateItem(item_id)
    local item_data = self.items[item_id]
    if not item_data then
        return false
    end

    -- 1x1 items don't need rotation (square)
    if item_data.width == item_data.height then
        return false
    end

    -- Store original dimensions
    local orig_x = item_data.x
    local orig_y = item_data.y
    local orig_width = item_data.width
    local orig_height = item_data.height
    local orig_rotated = item_data.rotated

    -- Remove from grid temporarily
    self:removeItem(item_id)

    -- Swap width and height
    local new_width = orig_height
    local new_height = orig_width

    -- Check if rotated item can fit at same position
    if self:canPlaceItem(orig_x, orig_y, new_width, new_height) then
        -- Rotation successful: place with new dimensions
        self:placeItem(item_id, item_data.item, orig_x, orig_y, new_width, new_height, not orig_rotated)
        return true
    else
        -- Rotation failed: restore original dimensions
        self:placeItem(item_id, item_data.item, orig_x, orig_y, orig_width, orig_height, orig_rotated)
        return false
    end
end

-- Legacy compatibility: select by slot number
function inventory:selectSlot(slot_index)
    local item_ids = {}
    for item_id, _ in pairs(self.items) do
        table.insert(item_ids, item_id)
    end

    -- Sort by grid position
    table.sort(item_ids, function(a, b)
        local item_a = self.items[a]
        local item_b = self.items[b]
        if item_a.y == item_b.y then
            return item_a.x < item_b.x
        end
        return item_a.y < item_b.y
    end)

    if slot_index >= 1 and slot_index <= #item_ids then
        self.selected_item_id = item_ids[slot_index]
        self.selected_slot = slot_index
    end
end

-- ============================================================================
-- Save/Load Functions
-- ============================================================================

function inventory:save()
    local grid_items = {}
    local equipped_items = {}

    -- Separate grid items and equipped items
    for item_id, item_data in pairs(self.items) do
        if item_data.equipped then
            -- Save equipped items separately (no x, y)
            table.insert(equipped_items, {
                uuid = item_id,
                type = item_data.item.type,
                quantity = item_data.item.quantity,
                width = item_data.width,
                height = item_data.height,
                rotated = item_data.rotated,
                slot = item_data.slot
            })
        else
            -- Save grid items with positions
            table.insert(grid_items, {
                uuid = item_id,
                type = item_data.item.type,
                quantity = item_data.item.quantity,
                x = item_data.x,
                y = item_data.y,
                width = item_data.width,
                height = item_data.height,
                rotated = item_data.rotated
            })
        end
    end

    return {
        items = grid_items,
        equipped_items = equipped_items,
        selected_item_id = self.selected_item_id,
        quickslots = self.quickslots
    }
end

function inventory:load(save_data)
    if not save_data then
        return
    end

    -- Clear existing inventory
    self.items = {}
    for y = 1, self.grid_height do
        for x = 1, self.grid_width do
            self.grid[y][x] = nil
        end
    end

    -- Clear equipment slots
    for slot_name, _ in pairs(self.equipment_slots) do
        self.equipment_slots[slot_name] = nil
    end

    -- Load grid items (items with x, y positions)
    if save_data.items then
        for _, item_data in ipairs(save_data.items) do
            local item_obj = self.item_class:new(item_data.type, item_data.quantity, item_data.uuid)
            self:placeItem(
                item_data.uuid,
                item_obj,
                item_data.x,
                item_data.y,
                item_data.width or item_obj.size.width,
                item_data.height or item_obj.size.height,
                item_data.rotated or false
            )
        end
    end

    -- Load equipped items (items in equipment slots, no x, y)
    if save_data.equipped_items then
        for _, item_data in ipairs(save_data.equipped_items) do
            local item_obj = self.item_class:new(item_data.type, item_data.quantity, item_data.uuid)

            -- Restore to equipment slot
            self.equipment_slots[item_data.slot] = item_data.uuid

            -- Store item data (without grid position)
            self.items[item_data.uuid] = {
                item = item_obj,
                width = item_data.width,
                height = item_data.height,
                rotated = item_data.rotated or false,
                equipped = true,
                slot = item_data.slot
            }
        end
    end

    self.selected_item_id = save_data.selected_item_id

    -- Load quickslots
    if save_data.quickslots then
        self.quickslots = save_data.quickslots
    else
        -- Initialize empty quickslots if not in save data (backward compatibility)
        self.quickslots = {nil, nil, nil, nil, nil}
    end
end

-- ============================================================================
-- Debug Functions
-- ============================================================================

function inventory:debugPrintGrid()
    print("=== Inventory Grid Debug ===")
    print(string.format("Grid size: %dx%d", self.grid_width, self.grid_height))
    print(string.format("Items count: %d", self:getItemCount()))

    -- Print grid visualization
    for y = 1, self.grid_height do
        local row = ""
        for x = 1, self.grid_width do
            if self.grid[y][x] then
                row = row .. "X "
            else
                row = row .. ". "
            end
        end
        print(row)
    end

    -- Print item details
    print("\n=== Items ===")
    for item_id, item_data in pairs(self.items) do
        print(string.format("%s: %s x%d at (%d,%d) size %dx%d",
            item_id:sub(1, 12),
            item_data.item.name,
            item_data.item.quantity,
            item_data.x,
            item_data.y,
            item_data.width,
            item_data.height
        ))
    end
    print("===========================")
end

function inventory:getItemCount()
    local count = 0
    for _ in pairs(self.items) do
        count = count + 1
    end
    return count
end

-- ============================================================================
-- Equipment Slot Functions
-- ============================================================================

-- Equip item to specific slot
function inventory:equipItem(item_id, slot_name, player)
    -- Validate item exists
    local item_data = self.items[item_id]
    if not item_data then
        return false, "Item not found"
    end

    local item = item_data.item

    -- Validate item is equippable
    if not item.equipment_slot then
        return false, "Item is not equippable"
    end

    -- Validate slot type matches
    if item.equipment_slot ~= slot_name then
        return false, "Wrong slot type"
    end

    -- Unequip existing item in slot (if any)
    if self.equipment_slots[slot_name] then
        local success, err = self:unequipItem(slot_name, player)
        if not success then
            return false, "Cannot unequip existing item: " .. (err or "unknown")
        end
    end

    -- Remove from grid
    self:removeItem(item_id)

    -- Place in equipment slot
    self.equipment_slots[slot_name] = item_id

    -- Store item data (but without grid position)
    self.items[item_id] = {
        item = item,
        width = item_data.width,
        height = item_data.height,
        rotated = item_data.rotated or false,
        equipped = true,
        slot = slot_name
    }

    -- Special handling for weapon slot
    if slot_name == "weapon" and item.weapon_type then
        if player and player.equipWeapon then
            local success = player:equipWeapon(item.weapon_type)
            if not success then
                -- Restore item to grid if weapon equip failed
                self:placeItem(item_id, item, item_data.x or 1, item_data.y or 1, item_data.width, item_data.height, item_data.rotated)
                return false, "Failed to equip weapon"
            end
        end
    end

    -- Apply equipment stats to player
    if player and item.stats then
        if player.applyEquipmentStats then
            player:applyEquipmentStats(item.stats)
        end
    end

    return true
end

-- Unequip item from slot
function inventory:unequipItem(slot_name, player)
    local item_id = self.equipment_slots[slot_name]
    if not item_id then
        return false, "Slot is empty"
    end

    local item_data = self.items[item_id]
    if not item_data then
        return false, "Item data not found"
    end

    -- Find empty space in grid
    local x, y = self:findEmptySpace(item_data.width, item_data.height)
    if not x or not y then
        return false, "No space in inventory"
    end

    -- Remove equipment stats from player
    local item = item_data.item
    if player and item.stats then
        if player.removeEquipmentStats then
            player:removeEquipmentStats(item.stats)
        end
    end

    -- Special handling for weapon slot
    if slot_name == "weapon" and item.weapon_type then
        if player and player.unequipWeapon then
            player:unequipWeapon()
        end
    end

    -- Remove from equipment slot
    self.equipment_slots[slot_name] = nil

    -- Place back in grid
    self:placeItem(item_id, item, x, y, item_data.width, item_data.height, item_data.rotated)

    return true
end

-- Check if item can be equipped to slot
function inventory:canEquipToSlot(item_id, slot_name)
    local item_data = self.items[item_id]
    if not item_data then
        return false
    end

    local item = item_data.item
    if not item.equipment_slot then
        return false
    end

    return item.equipment_slot == slot_name
end

-- Get equipped item in slot
function inventory:getEquippedItem(slot_name)
    local item_id = self.equipment_slots[slot_name]
    if not item_id then
        return nil
    end

    local item_data = self.items[item_id]
    if item_data then
        return item_data.item, item_id
    end

    return nil
end

-- ============================================================================
-- Quickslot Management Functions
-- ============================================================================

-- Assign item to quickslot
function inventory:assignQuickslot(slot_index, item_id)
    if slot_index < 1 or slot_index > 5 then
        return false, "Invalid quickslot index"
    end

    -- Check if item exists
    local item_data = self.items[item_id]
    if not item_data then
        return false, "Item not found"
    end

    -- Only allow usable items (potions, consumables)
    local item = item_data.item
    if not item.use or not item.canUse then
        -- Check if it's equipment
        if item.equipment_slot or item.item_type == "equipment" then
            return false, "Equipment cannot be assigned to quickslots"
        else
            return false, "Only consumable items can be assigned to quickslots"
        end
    end

    -- Assign to quickslot
    self.quickslots[slot_index] = item_id

    return true
end

-- Remove item from quickslot
function inventory:removeQuickslot(slot_index)
    if slot_index < 1 or slot_index > 5 then
        return false
    end

    self.quickslots[slot_index] = nil
    return true
end

-- Use item in quickslot
function inventory:useQuickslot(slot_index, player)
    if slot_index < 1 or slot_index > 5 then
        return false, "Invalid quickslot index"
    end

    local item_id = self.quickslots[slot_index]
    if not item_id then
        return false, "Quickslot is empty"
    end

    local item_data = self.items[item_id]
    if not item_data then
        -- Item was removed from inventory, clear quickslot
        self.quickslots[slot_index] = nil
        return false, "Item no longer exists"
    end

    local item = item_data.item

    -- Check if item can be used
    if not item.canUse or not item:canUse(player) then
        return false, "Cannot use item"
    end

    -- Use the item
    if item.use and item:use(player) then
        -- Decrease quantity or remove item
        if item.max_stack and item.max_stack > 1 then
            -- Stackable item - decrease quantity
            item_data.quantity = (item_data.quantity or 1) - 1
            if item_data.quantity <= 0 then
                -- Remove item completely
                self:removeItem(item_id)
                self.quickslots[slot_index] = nil
            end
        else
            -- Non-stackable item - remove completely
            self:removeItem(item_id)
            self.quickslots[slot_index] = nil
        end

        return true
    end

    return false, "Item use failed"
end

-- Get item in quickslot
function inventory:getQuickslotItem(slot_index)
    if slot_index < 1 or slot_index > 5 then
        return nil
    end

    local item_id = self.quickslots[slot_index]
    if not item_id then
        return nil
    end

    local item_data = self.items[item_id]
    if not item_data then
        -- Item temporarily doesn't exist (e.g., being dragged)
        -- Don't clear quickslot, just return nil
        -- Quickslot should only be cleared explicitly via removeQuickslot()
        -- or when item is consumed via useQuickslot()
        return nil
    end

    return item_data.item, item_id, item_data
end

return inventory

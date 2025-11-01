-- systems/inventory.lua
-- Inventory management system with item selection UI

local item_class = require "entities.item"

local inventory = {}
inventory.__index = inventory

function inventory:new()
    local instance = setmetatable({}, inventory)

    instance.items = {}
    instance.max_slots = 10
    instance.selected_slot = 1

    return instance
end

function inventory:addItem(item_type, quantity)
    quantity = quantity or 1

    -- Check if item already exists in inventory
    for i, item in ipairs(self.items) do
        if item.type == item_type then
            local overflow = item:addQuantity(quantity)
            if overflow > 0 then
                -- Create new stack if overflow
                if #self.items < self.max_slots then
                    table.insert(self.items, item_class:new(item_type, overflow))
                    print(string.format("Added %s x%d (new stack)", item.name, overflow))
                else
                    print("Inventory full!")
                    return false
                end
            end
            print(string.format("Added %s x%d", item.name, quantity - overflow))
            return true
        end
    end

    -- Add new item
    if #self.items < self.max_slots then
        table.insert(self.items, item_class:new(item_type, quantity))
        print(string.format("Added new item: %s x%d", item_class:new(item_type, 1).name, quantity))
        return true
    else
        print("Inventory full!")
        return false
    end
end

function inventory:removeItem(slot_index, quantity)
    quantity = quantity or 1

    if slot_index < 1 or slot_index > #self.items then
        return false
    end

    local item = self.items[slot_index]
    item.quantity = item.quantity - quantity

    if item.quantity <= 0 then
        table.remove(self.items, slot_index)
        if self.selected_slot > #self.items and self.selected_slot > 1 then
            self.selected_slot = self.selected_slot - 1
        end
    end

    return true
end

function inventory:getSelectedItem()
    if self.selected_slot < 1 or self.selected_slot > #self.items then
        return nil
    end
    return self.items[self.selected_slot]
end

function inventory:useSelectedItem(player)
    local item = self:getSelectedItem()
    if not item then
        return false
    end

    if not item:canUse(player) then
        print("Cannot use item right now!")
        return false
    end

    local success = item:use(player)
    if success then
        if item.quantity <= 0 then
            self:removeItem(self.selected_slot, 0)
        end
        return true
    end

    return false
end

function inventory:selectSlot(slot_index)
    if slot_index >= 1 and slot_index <= math.max(#self.items, 1) then
        self.selected_slot = slot_index
    end
end

function inventory:selectNext()
    if #self.items == 0 then
        return
    end

    self.selected_slot = self.selected_slot + 1
    if self.selected_slot > #self.items then
        self.selected_slot = 1
    end
end

function inventory:selectPrevious()
    if #self.items == 0 then
        return
    end

    self.selected_slot = self.selected_slot - 1
    if self.selected_slot < 1 then
        self.selected_slot = #self.items
    end
end

function inventory:save()
    local save_data = {}
    for i, item in ipairs(self.items) do
        table.insert(save_data, {
            type = item.type,
            quantity = item.quantity
        })
    end
    return {
        items = save_data,
        selected_slot = self.selected_slot
    }
end

function inventory:load(save_data)
    if not save_data then
        return
    end

    self.items = {}
    if save_data.items then
        for _, item_data in ipairs(save_data.items) do
            table.insert(self.items, item_class:new(item_data.type, item_data.quantity))
        end
    end

    self.selected_slot = save_data.selected_slot or 1
end

return inventory

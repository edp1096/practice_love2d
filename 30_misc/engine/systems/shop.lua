-- engine/systems/shop.lua
-- Shop system for managing shop data and transactions

local shop = {}

-- Shop data registry (injected from game/data/shops.lua)
shop.shops_data = nil

-- Runtime shop state (stock changes)
shop.shop_states = {}

-- Initialize shop system with data
function shop:init(shops_data)
    self.shops_data = shops_data or {}
    self.shop_states = {}
end

-- Get shop definition
function shop:getShop(shop_id)
    if not self.shops_data then return nil end
    return self.shops_data[shop_id]
end

-- Get current stock for an item in a shop
function shop:getStock(shop_id, item_type)
    local shop_def = self:getShop(shop_id)
    if not shop_def then return 0 end

    -- Check runtime state first
    if self.shop_states[shop_id] and self.shop_states[shop_id][item_type] ~= nil then
        return self.shop_states[shop_id][item_type]
    end

    -- Fall back to initial stock
    for _, item in ipairs(shop_def.items) do
        if item.type == item_type then
            return item.stock
        end
    end

    return 0
end

-- Get item price
function shop:getPrice(shop_id, item_type)
    local shop_def = self:getShop(shop_id)
    if not shop_def then return 0 end

    for _, item in ipairs(shop_def.items) do
        if item.type == item_type then
            return item.price
        end
    end

    return 0
end

-- Get sell price (based on sell_rate)
function shop:getSellPrice(shop_id, item_type)
    local shop_def = self:getShop(shop_id)
    if not shop_def then return 0 end

    local buy_price = self:getPrice(shop_id, item_type)
    local sell_rate = shop_def.sell_rate or 0.5

    return math.floor(buy_price * sell_rate)
end

-- Reduce stock after purchase
function shop:reduceStock(shop_id, item_type, amount)
    amount = amount or 1

    if not self.shop_states[shop_id] then
        self.shop_states[shop_id] = {}
    end

    local current = self:getStock(shop_id, item_type)
    self.shop_states[shop_id][item_type] = math.max(0, current - amount)
end

-- Increase stock (for restocking or selling to shop)
function shop:addStock(shop_id, item_type, amount)
    amount = amount or 1

    if not self.shop_states[shop_id] then
        self.shop_states[shop_id] = {}
    end

    local current = self:getStock(shop_id, item_type)
    self.shop_states[shop_id][item_type] = current + amount
end

-- Buy item from shop
-- Returns: success, error_message
function shop:buyItem(shop_id, item_type, level_system, inventory)
    local stock = self:getStock(shop_id, item_type)
    if stock <= 0 then
        return false, "Out of stock"
    end

    local price = self:getPrice(shop_id, item_type)
    if not level_system:hasGold(price) then
        return false, "Not enough gold"
    end

    -- Add to inventory
    local success = inventory:addItem(item_type, 1)
    if not success then
        return false, "Inventory full"
    end

    -- Deduct gold and reduce stock
    level_system:removeGold(price)
    self:reduceStock(shop_id, item_type, 1)

    return true, nil
end

-- Sell item to shop
-- Returns: success, error_message
function shop:sellItem(shop_id, item_id, level_system, inventory)
    local item_data = inventory.items[item_id]
    if not item_data then
        return false, "Item not found"
    end

    local item_type = item_data.item.type
    local sell_price = self:getSellPrice(shop_id, item_type)

    -- Remove from inventory
    local removed = inventory:removeItem(item_id, 1)
    if not removed then
        return false, "Failed to remove item"
    end

    -- Add gold
    level_system:addGold(sell_price)

    -- Optionally add to shop stock (commented out - shops don't buy back by default)
    -- self:addStock(shop_id, item_type, 1)

    return true, nil
end

-- Serialize shop state for saving
function shop:serialize()
    return {
        shop_states = self.shop_states
    }
end

-- Deserialize shop state from save
function shop:deserialize(data)
    if data and data.shop_states then
        self.shop_states = data.shop_states
    end
end

-- Reset shop states (for new game)
function shop:reset()
    self.shop_states = {}
end

return shop

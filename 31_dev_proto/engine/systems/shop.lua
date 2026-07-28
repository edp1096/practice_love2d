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
-- quantity: number of items to buy (default 1)
function shop:buyItem(shop_id, item_type, quantity, level_system, inventory)
    quantity = quantity or 1

    local stock = self:getStock(shop_id, item_type)
    if stock < quantity then
        return false, "Out of stock"
    end

    local price = self:getPrice(shop_id, item_type)
    local total_price = price * quantity
    if not level_system:hasGold(total_price) then
        return false, "Not enough gold"
    end

    -- Add to inventory
    local success = inventory:addItem(item_type, quantity)
    if not success then
        return false, "Inventory full"
    end

    -- Deduct gold and reduce stock
    level_system:removeGold(total_price)
    self:reduceStock(shop_id, item_type, quantity)

    return true, nil
end

-- Sell item to shop
-- Returns: success, error_message
-- quantity: number of items to sell (default 1)
function shop:sellItem(shop_id, item_type, quantity, level_system, inventory)
    quantity = quantity or 1

    -- Check if player has enough items
    local current_count = inventory:getItemCountByType(item_type)
    if current_count < quantity then
        return false, "Not enough items"
    end

    local sell_price = self:getSellPrice(shop_id, item_type)
    local total_price = sell_price * quantity

    -- Remove from inventory
    local removed = inventory:removeItemByType(item_type, quantity)
    if not removed then
        return false, "Failed to remove item"
    end

    -- Add gold
    level_system:addGold(total_price)

    -- Optionally add to shop stock (commented out - shops don't buy back by default)
    -- self:addStock(shop_id, item_type, quantity)

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

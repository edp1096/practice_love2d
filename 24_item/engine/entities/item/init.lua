-- entities/item/init.lua
-- Base item entity class

local item = {}
item.__index = item

function item:new(item_type, quantity)
    local instance = setmetatable({}, item)

    instance.type = item_type
    instance.quantity = quantity or 1

    -- Load item type configuration
    local item_config = require("engine.entities.item.types." .. item_type)
    instance.config = item_config
    instance.name = item_config.name
    instance.description = item_config.description
    instance.max_stack = item_config.max_stack or 99

    return instance
end

function item:use(player)
    if self.quantity <= 0 then
        return false
    end

    if self.config.use then
        local success = self.config.use(player)
        if success then
            self.quantity = self.quantity - 1
            return true
        end
    end

    return false
end

function item:canUse(player)
    if self.quantity <= 0 then
        return false
    end

    if self.config.canUse then
        return self.config.canUse(player)
    end

    return true
end

function item:addQuantity(amount)
    local new_quantity = self.quantity + amount
    if new_quantity > self.max_stack then
        local overflow = new_quantity - self.max_stack
        self.quantity = self.max_stack
        return overflow
    else
        self.quantity = new_quantity
        return 0
    end
end

return item

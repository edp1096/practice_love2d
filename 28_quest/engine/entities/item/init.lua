-- entities/item/init.lua
-- Base item entity class

local item = {}
item.__index = item

-- Item type registry (injected from game)
item.type_registry = {}

-- UUID generation counter
local uuid_counter = 0

-- Generate unique ID for item instances
local function generate_uuid()
    uuid_counter = uuid_counter + 1
    return string.format("item_%d_%d", os.time(), uuid_counter)
end

function item:new(item_type, quantity, uuid)
    local instance = setmetatable({}, item)

    -- Generate or use provided UUID
    instance.uuid = uuid or generate_uuid()
    instance.type = item_type
    instance.quantity = quantity or 1

    -- Load item type configuration from registry
    local item_config = item.type_registry[item_type]
    if not item_config then
        error(string.format("Unknown item type: %s (registry not initialized or item not registered)", item_type))
    end
    instance.config = item_config
    instance.name = item_config.name
    instance.description = item_config.description
    instance.max_stack = item_config.max_stack or 99

    -- Get item size from config (default 1x1)
    instance.size = item_config.size or { width = 1, height = 1 }

    -- Copy equipment properties (if this is equipment)
    instance.item_type = item_config.item_type  -- "equipment" or nil
    instance.equipment_slot = item_config.equipment_slot  -- "weapon", "helmet", etc.
    instance.weapon_type = item_config.weapon_type  -- "sword", "axe", etc.
    instance.sprite = item_config.sprite  -- Sprite info for rendering
    instance.stats = item_config.stats  -- Equipment stats

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
    -- Check quantity if available (quantity is stored in inventory item_data, not in item object)
    if self.quantity and self.quantity <= 0 then
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

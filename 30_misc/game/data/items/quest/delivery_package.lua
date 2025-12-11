-- game/data/items/quest/delivery_package.lua
-- Delivery package for A->B delivery quests (quest item - not usable)

local delivery_package = {
    name = "Delivery Package",
    name_key = "items.delivery_package.name",
    description = "A package to be delivered. Handle with care!",
    description_key = "items.delivery_package.description",
    size = { width = 1, height = 1 },
    max_stack = 1,

    -- UI color (for inventory/HUD display)
    color = {0.8, 0.6, 0.4, 1},  -- Brown

    -- Sprite information (using drink1 as placeholder until package.png is created)
    sprite = {
        file = "assets/images/sprites/items/drink1.png",
        x = 0,
        y = 0,
        w = 32,
        h = 32,
        scale = 1
    },

    -- Item type (quest item - cannot be used, sold, or dropped)
    item_type = "quest",

    -- No effects - this is a delivery item
    effects = {}
}

return delivery_package

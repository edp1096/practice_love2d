-- game/data/items/consumables/large_potion.lua
-- Large health potion configuration (pure data - no logic)

local large_potion = {
    name = "Large Health Potion",
    description = "Restores 60 HP",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 10,

    -- UI color (for inventory/HUD display)
    color = {0.3, 1, 0.8, 1},  -- Cyan green

    -- Sprite information (single image, not sprite sheet)
    sprite = {
        file = "assets/images/drink1.png",
        x = 0,
        y = 0,
        w = 32,
        h = 32,
        scale = 1
    },

    -- Item type (explicit declaration)
    item_type = "consumable",

    -- Use condition (explicit declaration)
    use_condition = {
        type = "health_not_full"
    },

    -- Effects when used (explicit declaration)
    effects = {
        { type = "heal", amount = 60 },
        { type = "play_sound", category = "item", name = "eat" }
    }
}

return large_potion

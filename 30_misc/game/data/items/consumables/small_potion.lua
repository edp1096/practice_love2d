-- game/data/items/consumables/small_potion.lua
-- Small health potion configuration (pure data - no logic)

local small_potion = {
    name = "Small Health Potion",
    description = "Restores 30 HP",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 20,

    -- UI color (for inventory/HUD display)
    color = {0.5, 1, 0.5, 1},  -- Light green

    -- Sprite information (single image, not sprite sheet)
    sprite = {
        file = "assets/images/sprites/items/energy-red.png",
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
        { type = "heal", amount = 30 },
        { type = "play_sound", category = "item", name = "eat" }
    }
}

return small_potion

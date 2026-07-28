-- game/data/items/consumables/orange.lua
-- Orange (medium healing fruit) - pure data, no logic

local orange = {
    name = "Orange",
    name_key = "items.orange.name",
    description = "Restores 20 HP",
    description_key = "items.orange.description",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 99,

    -- Sprite information for world item (animation)
    sprite = {
        file = "assets/images/sprites/items/orange.png",
        width = 32,
        height = 32,
        frames = 17,  -- Total animation frames
        duration = 0.1,  -- Animation speed (per frame)

        -- Inventory display (first frame only)
        x = 0,  -- First frame column
        y = 0,  -- First row
        w = 32, -- Frame width
        h = 32, -- Frame height
        scale = 1  -- 1:1 scale
    },

    -- Item type (explicit declaration)
    item_type = "consumable",

    -- Use condition (explicit declaration)
    use_condition = {
        type = "health_not_full"
    },

    -- Effects when used (explicit declaration)
    effects = {
        { type = "heal", amount = 20 },
        { type = "play_sound", category = "item", name = "eat" }
    }
}

return orange

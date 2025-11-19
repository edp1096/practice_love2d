-- game/data/items/weapons/iron_sword.lua
-- Iron sword equipment configuration (pure data - no logic)

local iron_sword = {
    name = "Iron Sword",
    description = "A sturdy iron sword",
    size = { width = 1, height = 1 },  -- Grid size: 1x1 (16x16 sprite)
    max_stack = 1,  -- Equipment cannot be stacked

    -- Item type (explicit declaration)
    item_type = "equipment",
    equipment_slot = "weapon",  -- Can only be equipped to weapon slot

    -- Weapon type for player weapon system
    weapon_type = "sword",  -- Must match game/data/entities/types.lua weapons table

    -- Sprite information for rendering (from steel-weapons.png)
    sprite = {
        file = "assets/images/steel-weapons.png",
        x = 0,      -- Top-left X in sprite sheet
        y = 0,      -- Top-left Y in sprite sheet
        w = 16,     -- Width in pixels
        h = 16,     -- Height in pixels
        scale = 3   -- Render scale
    },

    -- Equipment stats (applied when equipped)
    stats = {
        damage = 15,
        attack_speed = 1.0
    },

    -- Use condition (explicit declaration - equipment cannot be used)
    use_condition = {
        type = "never"
    }
}

return iron_sword

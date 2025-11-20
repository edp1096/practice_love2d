-- game/data/items/weapons/iron_axe.lua
-- Iron axe equipment configuration (pure data - no logic)

local iron_axe = {
    name = "Iron Axe",
    description = "A heavy iron axe",
    size = { width = 1, height = 1 },  -- Grid size: 1x1 (16x16 sprite)
    max_stack = 1,  -- Equipment cannot be stacked

    -- Item type (explicit declaration)
    item_type = "equipment",
    equipment_slot = "weapon",  -- Can only be equipped to weapon slot

    -- Weapon type for player weapon system
    weapon_type = "axe",  -- Must match game/data/entities/types.lua weapons table

    -- Sprite information for rendering (from weapon-steel.png)
    sprite = {
        file = "assets/images/sprites/weapons/weapon-steel.png",
        x = 0,      -- 1x11: Row 1 (index 0)
        y = 160,    -- 1x11: Column 11 (index 10 * 16 = 160)
        w = 16,     -- Width in pixels
        h = 16,     -- Height in pixels
        scale = 3   -- Render scale
    },

    -- Equipment stats (applied when equipped)
    stats = {
        damage = 20,  -- Higher damage than sword
        attack_speed = 0.8  -- Slower than sword
    },

    -- Use condition (explicit declaration - equipment cannot be used)
    use_condition = {
        type = "never"
    }
}

return iron_axe

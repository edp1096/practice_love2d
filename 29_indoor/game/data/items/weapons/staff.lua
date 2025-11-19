-- game/data/items/weapons/staff.lua
-- Staff equipment configuration (pure data - no logic)

local staff = {
    name = "Staff",
    description = "A long wooden staff",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 1,  -- Equipment cannot be stacked

    -- Item type (explicit declaration)
    item_type = "equipment",
    equipment_slot = "weapon",  -- Can only be equipped to weapon slot

    -- Weapon type for player weapon system
    weapon_type = "staff",  -- Must match game/data/entities/types.lua weapons table

    -- Sprite information for rendering (from steel-weapons.png)
    sprite = {
        file = "assets/images/steel-weapons.png",
        x = 288,    -- Column 19 (index 18 * 16 = 288)
        y = 0,      -- Row 1 (index 0 * 16 = 0)
        w = 16,     -- Width in pixels
        h = 16,     -- Height in pixels
        scale = 3   -- Render scale
    },

    -- Equipment stats (applied when equipped)
    stats = {
        damage = 8,   -- Lower damage than sword
        attack_speed = 1.5,  -- Fastest attack speed
        range = 1.2  -- Longer reach
    },

    -- Use condition (explicit declaration - equipment cannot be used)
    use_condition = {
        type = "never"
    }
}

return staff

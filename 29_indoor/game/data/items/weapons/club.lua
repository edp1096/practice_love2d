-- game/data/items/weapons/club.lua
-- Club equipment configuration (pure data - no logic)

local club = {
    name = "Club",
    description = "A simple wooden club",
    size = { width = 1, height = 1 },  -- Grid size: 1x1 (16x16 sprite)
    max_stack = 1,  -- Equipment cannot be stacked

    -- Item type (explicit declaration)
    item_type = "equipment",
    equipment_slot = "weapon",  -- Can only be equipped to weapon slot

    -- Weapon type for player weapon system
    weapon_type = "club",  -- Must match game/data/entities/types.lua weapons table

    -- Sprite information for rendering (from steel-weapons.png)
    sprite = {
        file = "assets/images/steel-weapons.png",
        x = 48,     -- 4x11: Row 4 (index 3 * 16 = 48)
        y = 160,    -- 4x11: Column 11 (index 10 * 16 = 160)
        w = 16,     -- Width in pixels
        h = 16,     -- Height in pixels
        scale = 3   -- Render scale
    },

    -- Equipment stats (applied when equipped)
    stats = {
        damage = 12,  -- Lower damage than sword
        attack_speed = 1.2  -- Faster than sword
    },

    -- Use condition (explicit declaration - equipment cannot be used)
    use_condition = {
        type = "never"
    }
}

return club

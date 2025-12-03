-- game/data/items/weapons/magic_staff.lua
-- Magic staff equipment configuration - Enhanced version of regular staff

local magic_staff = {
    name = "Magic Staff",
    name_key = "items.magic_staff.name",
    description = "A staff imbued with magic",
    description_key = "items.magic_staff.description",
    size = { width = 1, height = 1 },  -- Grid size: 1x1
    max_stack = 1,  -- Equipment cannot be stacked

    -- Item type (explicit declaration)
    item_type = "equipment",
    equipment_slot = "weapon",  -- Can only be equipped to weapon slot

    -- Weapon type for player weapon system
    weapon_type = "staff",  -- Must match game/data/entities/types.lua weapons table

    -- Sprite information for rendering (from weapon-steel.png)
    sprite = {
        file = "assets/images/sprites/weapons/weapon-steel.png",
        x = 288,    -- Column 19 (index 18 * 16 = 288)
        y = 0,      -- Row 1 (index 0 * 16 = 0)
        w = 16,     -- Width in pixels
        h = 16,     -- Height in pixels
        scale = 2   -- Render scale
    },

    -- Equipment stats (applied when equipped)
    -- Base stats come from game/data/entities/types.lua
    -- These are bonuses/multipliers applied on top
    stats = {
        damage = 18,           -- +18 damage (higher than regular staff +8)
        attack_speed = 1.6,    -- 1.6x speed (60% faster, even faster than regular staff)
        range = 1.4,           -- 1.4x range (40% longer reach - enhanced)
        swing_radius = 1.2     -- 1.2x swing radius (20% larger - enhanced)
    },

    -- Use condition (explicit declaration - equipment cannot be used)
    use_condition = {
        type = "never"
    }
}

return magic_staff

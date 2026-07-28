-- game/data/items/weapons/mystic_staff.lua
-- Mystic staff equipment configuration - Ultimate staff variant

local mystic_staff = {
    name = "Mystic Staff",
    name_key = "items.mystic_staff.name",
    description = "A powerful mystic staff",
    description_key = "items.mystic_staff.description",
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
        damage = 25,           -- +25 damage (highest of all staffs)
        attack_speed = 1.8,    -- 1.8x speed (80% faster, ultimate speed)
        range = 1.6,           -- 1.6x range (60% longer reach - ultimate)
        swing_radius = 1.4     -- 1.4x swing radius (40% larger - ultimate)
    },

    -- Use condition (explicit declaration - equipment cannot be used)
    use_condition = {
        type = "never"
    }
}

return mystic_staff

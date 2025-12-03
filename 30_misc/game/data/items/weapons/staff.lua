-- game/data/items/weapons/staff.lua
-- Staff equipment configuration (pure data - no logic)

local staff = {
    name = "Wooden Staff",
    name_key = "items.staff.name",
    description = "A basic wooden staff",
    description_key = "items.staff.description",
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
        damage = 8,            -- +8 damage (additive, lowest damage)
        attack_speed = 1.5,    -- 1.5x speed (50% faster, fastest weapon)
        range = 1.2,           -- 1.2x range (20% longer reach)
        swing_radius = 1.1     -- 1.1x swing radius (10% larger)
    },

    -- Use condition (explicit declaration - equipment cannot be used)
    use_condition = {
        type = "never"
    }
}

return staff

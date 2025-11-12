-- entities/item/types/iron_sword.lua
-- Iron sword equipment configuration

local iron_sword = {
    name = "Iron Sword",
    description = "A sturdy iron sword",
    size = { width = 1, height = 3 },  -- Grid size: 1x3 (tall weapon)
    item_type = "equipment",
    equipment_slot = "weapon",  -- Can only be equipped to weapon slot
    max_stack = 1,  -- Equipment cannot be stacked

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
    }
}

function iron_sword.use(player)
    -- Equipment items don't have "use" - they are equipped via drag & drop
    -- But we keep this function for compatibility
    return false
end

function iron_sword.canUse(player)
    -- Equipment cannot be "used" directly
    return false
end

return iron_sword

-- entities/item/types/iron_axe.lua
-- Iron axe equipment configuration

local iron_axe = {
    name = "Iron Axe",
    description = "A heavy iron axe",
    size = { width = 1, height = 1 },  -- Grid size: 1x1 (16x16 sprite)
    item_type = "equipment",
    equipment_slot = "weapon",  -- Can only be equipped to weapon slot
    max_stack = 1,  -- Equipment cannot be stacked

    -- Weapon type for player weapon system
    weapon_type = "axe",  -- Must match game/data/entities/types.lua weapons table

    -- Sprite information for rendering (from steel-weapons.png)
    sprite = {
        file = "assets/images/steel-weapons.png",
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
    }
}

function iron_axe.use(player)
    -- Equipment items don't have "use" - they are equipped via drag & drop
    return false
end

function iron_axe.canUse(player)
    -- Equipment cannot be "used" directly
    return false
end

return iron_axe

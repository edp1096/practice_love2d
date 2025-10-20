-- entities/weapon/types/sword.lua
-- Sword weapon type configuration

local sword = {}

sword.WEAPON_TYPES = {
    sword = {
        sprite_file = "assets/images/steel-weapons.png",
        sprite_x = 0,
        sprite_y = 0,
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        -- Attack animation properties
        attack_duration = 0.3,
        swing_radius = 35,

        -- Damage and range
        damage = 25,
        range = 80,
        knockback = 100,

        -- Hit timing
        hit_start = 0.3,
        hit_end = 0.7
    }
}

return sword

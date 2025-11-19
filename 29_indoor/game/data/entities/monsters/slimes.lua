-- game/data/entities/monsters/slimes.lua
-- Slime monster variants

return {
    red_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 100,
        damage = 10,
        speed = 100,
        attack_cooldown = 1.0,
        detection_range = 240,
        attack_range = 50,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -112,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = nil,
        target_color = nil
    },

    green_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 80,
        damage = 8,
        speed = 120,
        attack_cooldown = 0.8,
        detection_range = 220,
        attack_range = 50,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -112,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 1.0, 0.0 }
    },

    blue_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 120,
        damage = 12,
        speed = 80,
        attack_cooldown = 1.2,
        detection_range = 260,
        attack_range = 50,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 20,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -108,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 0.5, 1.0 }
    },

    purple_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 150,
        damage = 15,
        speed = 90,
        attack_cooldown = 1.5,
        detection_range = 290,
        attack_range = 60,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 20,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -108,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.8, 0.0, 1.0 }
    },
}

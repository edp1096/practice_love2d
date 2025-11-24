-- game/data/entities/monsters/slimes.lua
-- Slime monster variants

return {
    red_slime = {
        sprite_sheet = "assets/images/sprites/enemies/enemy-sheet-slime-red.png",
        health = 100,
        damage = 10,
        speed = 100,
        attack_cooldown = 1.0,
        detection_range = 240,
        attack_range = 50,
        loot_category = "slime",  -- For loot system

        sprite_width = 16,           -- Frame width
        sprite_height = 32,          -- Frame height (16x2 for jump animation)
        sprite_scale = 4,

        -- Actual character size: 16x16 (no padding, but uses 16x32 frame for jump)
        -- Character is at bottom 16px of the 16x32 frame (top 16px for jump animation)
        character_width = 16,
        character_height = 16,

        -- Collider will be auto-calculated as character_size * scale
        -- collider_width auto-calculated: 16 * 4 = 64
        -- collider_height auto-calculated: 16 * 4 = 64
        collider_offset_x = 0,
        collider_offset_y = 0,

        -- Sprite offset: character at bottom of frame requires manual offset
        -- Rendered sprite: 16*4 x 32*4 = 64x128
        -- Collider: 64x64 (at bottom 64px of sprite)
        -- Sprite top should be at collider_center_y - 96
        sprite_draw_offset_x = -32,  -- -(16*4 - 64)/2 = -32
        sprite_draw_offset_y = -96,  -- sprite top is 96px above collider center

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = nil,
        target_color = nil
    },

    green_slime = {
        sprite_sheet = "assets/images/sprites/enemies/enemy-sheet-slime-red.png",
        health = 80,
        damage = 8,
        speed = 120,
        attack_cooldown = 0.8,
        detection_range = 220,
        attack_range = 50,
        loot_category = "slime",

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,
        character_width = 16,
        character_height = 16,

        -- collider_width auto-calculated: 16 * 4 = 64
        -- collider_height auto-calculated: 16 * 4 = 64
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 1.0, 0.0 }
    },

    blue_slime = {
        sprite_sheet = "assets/images/sprites/enemies/enemy-sheet-slime-red.png",
        health = 120,
        damage = 12,
        speed = 80,
        attack_cooldown = 1.2,
        detection_range = 260,
        attack_range = 50,
        loot_category = "slime",

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,
        character_width = 16,
        character_height = 16,

        -- collider_width auto-calculated: 16 * 4 = 64
        -- collider_height auto-calculated: 16 * 4 = 64
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -86,  -- -96 + 10 (collider_offset_y)

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 0.5, 1.0 }
    },

    purple_slime = {
        sprite_sheet = "assets/images/sprites/enemies/enemy-sheet-slime-red.png",
        health = 150,
        damage = 15,
        speed = 90,
        attack_cooldown = 1.5,
        detection_range = 290,
        attack_range = 60,
        loot_category = "slime",

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,
        character_width = 16,
        character_height = 16,

        -- collider_width auto-calculated: 16 * 4 = 64
        -- collider_height auto-calculated: 16 * 4 = 64
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -86,  -- -96 + 10 (collider_offset_y)

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.8, 0.0, 1.0 }
    },
}

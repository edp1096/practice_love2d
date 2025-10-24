-- entities/enemy/types/humanoid.lua
-- Humanoid enemy type configurations

local humanoid = {}

humanoid.ENEMY_TYPES = {
    bandit = {
        sprite_sheet = "assets/images/player-sheet.png",
        health = 120,
        damage = 15,
        speed = 120,
        attack_cooldown = 1.2,
        detection_range = 250,
        attack_range = 60,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 40,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = nil,
        target_color = nil,

        -- Animation frames (row, columns)
        idle_up = "5-8",
        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_row_up = 1,
        idle_row_down = 1,
        idle_row_left = 2,
        idle_row_right = 2,

        walk_up = "1-4",
        walk_down = "1-4",
        walk_left = "5-8,1-2",
        walk_right = "3-8",
        walk_row_up = 4,
        walk_row_down = 3,
        walk_row_left = "4,5",
        walk_row_right = 5,

        attack_up = "5-8",
        attack_down = "1-4",
        attack_left = "1-4",
        attack_right = "5-8",
        attack_row_up = 11,
        attack_row_down = 11,
        attack_row_left = 12,
        attack_row_right = 12,
    },

    rogue = {
        sprite_sheet = "assets/images/player-sheet.png",
        health = 100,
        damage = 12,
        speed = 150,
        attack_cooldown = 0.9,
        detection_range = 280,
        attack_range = 55,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 40,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 0.8, 0.4, 0.2 },
        target_color = { 0.2, 0.2, 0.2 },

        idle_up = "5-8",
        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_row_up = 1,
        idle_row_down = 1,
        idle_row_left = 2,
        idle_row_right = 2,

        walk_up = "1-4",
        walk_down = "1-4",
        walk_left = "5-8,1-2",
        walk_right = "3-8",
        walk_row_up = 4,
        walk_row_down = 3,
        walk_row_left = "4,5",
        walk_row_right = 5,

        attack_up = "5-8",
        attack_down = "1-4",
        attack_left = "1-4",
        attack_right = "5-8",
        attack_row_up = 11,
        attack_row_down = 11,
        attack_row_left = 12,
        attack_row_right = 12,
    },

    warrior = {
        sprite_sheet = "assets/images/player-sheet.png",
        health = 150,
        damage = 20,
        speed = 100,
        attack_cooldown = 1.5,
        detection_range = 230,
        attack_range = 65,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 40,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 0.8, 0.4, 0.2 },
        target_color = { 0.6, 0.1, 0.1 },

        idle_up = "5-8",
        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_row_up = 4,
        idle_row_down = 3,
        idle_row_left = 4,
        idle_row_right = 5,

        walk_up = "1-4",
        walk_down = "1-4",
        walk_left = "5-8,1-2",
        walk_right = "3-8",
        walk_row_up = 4,
        walk_row_down = 3,
        walk_row_left = "4,5",
        walk_row_right = 5,

        attack_up = "5-8",
        attack_down = "1-4",
        attack_left = "1-4",
        attack_right = "5-8",
        attack_row_up = 11,
        attack_row_down = 11,
        attack_row_left = 12,
        attack_row_right = 12,
    },

    guard = {
        sprite_sheet = "assets/images/passerby_01-sheet.png",
        health = 140,
        damage = 18,
        speed = 110,
        attack_cooldown = 1.3,
        detection_range = 240,
        attack_range = 60,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 40,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = nil,
        target_color = nil,

        idle_up = "5-8",
        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_row_up = 1,
        idle_row_down = 1,
        idle_row_left = 2,
        idle_row_right = 2,

        walk_up = "1-4",
        walk_down = "1-4",
        walk_left = "5-8,1-2",
        walk_right = "3-8",
        walk_row_up = 4,
        walk_row_down = 3,
        walk_row_left = "4,5",
        walk_row_right = 5,

        attack_up = "5-8",
        attack_down = "1-4",
        attack_left = "1-4",
        attack_right = "5-8",
        attack_row_up = 11,
        attack_row_down = 11,
        attack_row_left = 12,
        attack_row_right = 12,
    },
}

return humanoid

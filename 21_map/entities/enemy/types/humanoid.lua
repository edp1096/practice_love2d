-- entities/enemy/types/humanoid.lua
-- Humanoid enemy type configurations

local humanoid = {}

humanoid.ENEMY_TYPES = {
    bandit = {
        sprite_sheet = "assets/images/enemy-sheet-human.png",
        health = 120,
        damage = 15,
        speed = 120,
        attack_cooldown = 1.2,
        detection_range = 250,
        attack_range = 35,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 80,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = nil,
        target_color = nil,

        -- Animation frames
        idle_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        idle_rows = { up = 1, down = 1, left = 2, right = 2 },

        walk_frames = { up = "1-4", down = "1-4", left = { "5-8", "1-2" }, right = "3-8" },
        walk_rows = { up = 4, down = 3, left = { 4, 5 }, right = 5 },

        attack_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        attack_rows = { up = 11, down = 11, left = 12, right = 12 },
    },

    rogue = {
        sprite_sheet = "assets/images/player-sheet.png",
        health = 100,
        damage = 12,
        speed = 150,
        attack_cooldown = 0.9,
        detection_range = 280,
        attack_range = 35,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 80,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = { 0.8, 0.4, 0.2 },
        target_color = { 0.2, 0.2, 0.2 },

        idle_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        idle_rows = { up = 1, down = 1, left = 2, right = 2 },

        walk_frames = { up = "1-4", down = "1-4", left = { "5-8", "1-2" }, right = "3-8" },
        walk_rows = { up = 4, down = 3, left = { 4, 5 }, right = 5 },

        attack_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        attack_rows = { up = 11, down = 11, left = 12, right = 12 },
    },

    warrior = {
        sprite_sheet = "assets/images/player-sheet.png",
        health = 150,
        damage = 20,
        speed = 100,
        attack_cooldown = 1.5,
        detection_range = 230,
        attack_range = 35,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 80,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = { 0.8, 0.4, 0.2 },
        target_color = { 0.6, 0.1, 0.1 },

        idle_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        idle_rows = { up = 4, down = 3, left = 4, right = 5 },

        walk_frames = { up = "1-4", down = "1-4", left = { "5-8", "1-2" }, right = "3-8" },
        walk_rows = { up = 4, down = 3, left = { 4, 5 }, right = 5 },

        attack_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        attack_rows = { up = 11, down = 11, left = 12, right = 12 },
    },

    guard = {
        sprite_sheet = "assets/images/passerby_01-sheet.png",
        health = 140,
        damage = 18,
        speed = 110,
        attack_cooldown = 1.3,
        detection_range = 240,
        attack_range = 35,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 40,
        collider_height = 80,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = nil,
        target_color = nil,

        idle_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        idle_rows = { up = 1, down = 1, left = 2, right = 2 },

        walk_frames = { up = "1-4", down = "1-4", left = { "5-8", "1-2" }, right = "3-8" },
        walk_rows = { up = 4, down = 3, left = { 4, 5 }, right = 5 },

        attack_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        attack_rows = { up = 11, down = 11, left = 12, right = 12 },
    },
}

return humanoid

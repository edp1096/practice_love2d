-- game/data/entities/humans/bandits.lua
-- Hostile humanoid enemies

-- Common animation frames for player-sheet layout
local player_sheet_anims = {
    idle_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
    idle_rows = { up = 1, down = 1, left = 2, right = 2 },
    walk_frames = { up = "1-4", down = "1-4", left = { "5-8", "1-2" }, right = "3-8" },
    walk_rows = { up = 4, down = 3, left = { 4, 5 }, right = 5 },
    attack_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
    attack_rows = { up = 11, down = 11, left = 12, right = 12 },
}

return {
    bandit = {
        sprite_sheet = "assets/images/sprites/enemies/enemy-sheet-human.png",
        health = 120,
        damage = 15,
        speed = 120,
        attack_cooldown = 1.2,
        detection_range = 290,
        attack_range = 35,
        loot_category = "humanoid",  -- For loot system

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,
        character_width = 16,
        character_height = 32,
        character_width = 16,
        character_height = 32,

        -- collider_width auto-calculated: 16 * 3 = 48
        -- collider_height auto-calculated: 32 * 3 = 96
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = nil,
        target_color = nil,

        idle_frames = player_sheet_anims.idle_frames,
        idle_rows = player_sheet_anims.idle_rows,
        walk_frames = player_sheet_anims.walk_frames,
        walk_rows = player_sheet_anims.walk_rows,
        attack_frames = player_sheet_anims.attack_frames,
        attack_rows = player_sheet_anims.attack_rows,

        -- Surrender settings (Enemy → NPC transformation)
        surrender_threshold = 0.3,  -- Surrender when HP <= 30%
        surrender_npc = "surrendered_bandit",  -- Transform to this NPC type
    },

    rogue = {
        sprite_sheet = "assets/images/player/player-sheet.png",
        health = 100,
        damage = 12,
        speed = 150,
        attack_cooldown = 0.9,
        detection_range = 320,
        attack_range = 35,
        loot_category = "humanoid",

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,
        character_width = 16,
        character_height = 32,
        character_width = 16,
        character_height = 32,

        -- collider_width auto-calculated: 16 * 3 = 48
        -- collider_height auto-calculated: 32 * 3 = 96
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = { 0.8, 0.4, 0.2 },
        target_color = { 0.2, 0.2, 0.2 },

        idle_frames = player_sheet_anims.idle_frames,
        idle_rows = player_sheet_anims.idle_rows,
        walk_frames = player_sheet_anims.walk_frames,
        walk_rows = player_sheet_anims.walk_rows,
        attack_frames = player_sheet_anims.attack_frames,
        attack_rows = player_sheet_anims.attack_rows,
    },

    warrior = {
        sprite_sheet = "assets/images/player/player-sheet.png",
        health = 150,
        damage = 20,
        speed = 100,
        attack_cooldown = 1.5,
        detection_range = 270,
        attack_range = 35,
        loot_category = "humanoid",

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,
        character_width = 16,
        character_height = 32,
        character_width = 16,
        character_height = 32,

        -- collider_width auto-calculated: 16 * 3 = 48
        -- collider_height auto-calculated: 32 * 3 = 96
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = { 0.8, 0.4, 0.2 },
        target_color = { 0.6, 0.1, 0.1 },

        idle_frames = player_sheet_anims.idle_frames,
        idle_rows = { up = 4, down = 3, left = 4, right = 5 },
        walk_frames = player_sheet_anims.walk_frames,
        walk_rows = player_sheet_anims.walk_rows,
        attack_frames = player_sheet_anims.attack_frames,
        attack_rows = player_sheet_anims.attack_rows,
    },

    -- Guard (enemy variant - when provoked)
    guard = {
        sprite_sheet = "assets/images/sprites/npcs/npc-passerby_01-sheet.png",
        health = 140,
        damage = 18,
        speed = 110,
        attack_cooldown = 1.3,
        detection_range = 280,
        attack_range = 35,
        loot_category = "humanoid",

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,
        character_width = 16,
        character_height = 32,
        character_width = 16,
        character_height = 32,

        -- collider_width auto-calculated: 16 * 3 = 48
        -- collider_height auto-calculated: 32 * 3 = 96
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = 0,
        sprite_draw_offset_y = -10,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        source_color = nil,
        target_color = nil,

        idle_frames = player_sheet_anims.idle_frames,
        idle_rows = player_sheet_anims.idle_rows,
        walk_frames = player_sheet_anims.walk_frames,
        walk_rows = player_sheet_anims.walk_rows,
        attack_frames = player_sheet_anims.attack_frames,
        attack_rows = player_sheet_anims.attack_rows,
    },
}

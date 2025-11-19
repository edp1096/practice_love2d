-- game/data/entity_types.lua
-- Centralized entity type definitions for all game entities
-- Engine uses this data via dependency injection (no engine -> game imports)
--
-- ========================================
-- COORDINATE SYSTEM GUIDE
-- ========================================
--
-- Entity positioning uses three offset fields:
--
-- 1. collider_offset_x/y
--    Offset from Tiled object position (top-left) → Collider center
--    Usually (0, 0) to place collider at Tiled object position
--
-- 2. sprite_draw_offset_x/y
--    Offset from Collider center → Sprite draw position
--    Usually negative to center large sprite on small collider
--    Auto-calculated if omitted: -(sprite_size*scale - collider_size)/2
--
-- 3. sprite_origin_x/y
--    Pivot point within sprite image (for rotation)
--    (0, 0) = top-left corner
--    (sprite_width/2, sprite_height/2) = center
--
-- TIP: Use Hand Marking tool to find correct values:
--   F1 (debug) → H (hand marking) → PgUp/PgDn (navigate frames) → P (mark position)
--
-- For detailed explanation, see: docs/GUIDE.md "Entity Coordinate System"
-- ========================================

local entity_types = {}

-- Enemy type definitions
entity_types.enemies = {
    -- Slime variants
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

    -- Humanoid variants
    bandit = {
        sprite_sheet = "assets/images/enemy-sheet-human.png",
        health = 120,
        damage = 15,
        speed = 120,
        attack_cooldown = 1.2,
        detection_range = 290,
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

        -- Surrender settings (Enemy → NPC transformation)
        surrender_threshold = 0.3,  -- Surrender when HP <= 30%
        surrender_npc = "surrendered_bandit",  -- Transform to this NPC type
    },

    rogue = {
        sprite_sheet = "assets/images/player-sheet.png",
        health = 100,
        damage = 12,
        speed = 150,
        attack_cooldown = 0.9,
        detection_range = 320,
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
        detection_range = 270,
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

    -- Deceiver (NPC → Enemy transformation demo)
    deceiver = {
        sprite_sheet = "assets/images/deceiver-sheet.png",
        health = 100,
        damage = 12,
        speed = 110,
        attack_cooldown = 1.0,
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

        source_color = nil,
        target_color = nil,

        -- Animation frames (same layout as player/enemy-sheet-human)
        idle_frames = { up = "5-8", down = "1-4", left = "1-4", right = "5-8" },
        idle_rows = { up = 1, down = 1, left = 2, right = 2 },

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

-- NPC type definitions
entity_types.npcs = {
    merchant = {
        name = "Merchant",
        sprite_sheet = "assets/images/player-sheet.png",
        dialogue = {
            "Hello player!",
        },
        interaction_range = 80,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 32,
        collider_offset_y = 32,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -128,

        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_up = "5-8",
        idle_row_down = 1,
        idle_row_left = 2,
        idle_row_right = 2,
        idle_row_up = 1,
    },

    guard = {
        name = "Guard",
        sprite_sheet = "assets/images/player-sheet.png",
        dialogue = {
            "Hello player!",
        },
        interaction_range = 70,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 32,
        collider_offset_y = 32,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -104,

        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_up = "5-8",
        idle_row_down = 3,
        idle_row_left = 4,
        idle_row_right = 5,
        idle_row_up = 4,
    },

    villager = {
        name = "Villager",
        sprite_sheet = "assets/images/passerby_01-sheet.png",
        -- Use dialogue tree instead of simple dialogue array
        dialogue_id = "villager_greeting",  -- References game/data/dialogues.lua
        interaction_range = 80,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 32,
        collider_offset_y = 32,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -104,

        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_up = "5-8",
        idle_row_down = 1,
        idle_row_left = 2,
        idle_row_right = 2,
        idle_row_up = 1,
    },

    elder = {
        name = "Village Elder",
        sprite_sheet = "assets/images/player-sheet.png",
        dialogue = {
            "Hello player!",
        },
        interaction_range = 90,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 32,
        collider_offset_y = 32,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -104,

        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_up = "5-8",
        idle_row_down = 3,
        idle_row_left = 4,
        idle_row_right = 5,
        idle_row_up = 4,
    },

    surrendered_bandit = {
        name = "Surrendered Bandit",
        sprite_sheet = "assets/images/enemy-sheet-human.png",
        dialogue_id = "surrendered_bandit",  -- References game/data/dialogues.lua
        interaction_range = 80,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 32,
        collider_offset_y = 32,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -104,

        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_up = "5-8",
        idle_row_down = 1,
        idle_row_left = 2,
        idle_row_right = 2,
        idle_row_up = 1,
    },

    deceiver = {
        name = "???",
        sprite_sheet = "assets/images/deceiver-sheet.png",
        dialogue_id = "deceiver_greeting",  -- References game/data/dialogues.lua
        interaction_range = 80,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 32,
        collider_offset_y = 32,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -104,

        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_up = "5-8",
        idle_row_down = 1,
        idle_row_left = 2,
        idle_row_right = 2,
        idle_row_up = 1,
    },
}

-- Weapon type definitions
entity_types.weapons = {
    sword = {
        sprite_file = "assets/images/steel-weapons.png",
        sprite_x = 0,
        sprite_y = 0,
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.3,
        swing_radius = 35,

        damage = 25,
        range = 80,
        knockback = 100,

        hit_start = 0.3,
        hit_end = 0.7
    },

    axe = {
        sprite_file = "assets/images/steel-weapons.png",
        sprite_x = 0,    -- 1x11: Row 1 (y coordinate)
        sprite_y = 160,  -- 1x11: Column 11 (x coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.4,
        swing_radius = 40,

        damage = 35,
        range = 85,
        knockback = 150,

        hit_start = 0.35,
        hit_end = 0.75
    },

    club = {
        sprite_file = "assets/images/steel-weapons.png",
        sprite_x = 48,   -- 4x11: Row 4 (y coordinate)
        sprite_y = 160,  -- 4x11: Column 11 (x coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.25,  -- Fast attack
        swing_radius = 30,

        damage = 20,  -- Lower damage
        range = 75,
        knockback = 80,

        hit_start = 0.25,
        hit_end = 0.65
    },

    staff = {
        sprite_file = "assets/images/steel-weapons.png",
        sprite_x = 288,  -- 19x1: Column 19 (x coordinate)
        sprite_y = 0,    -- 19x1: Row 1 (y coordinate)
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        attack_duration = 0.2,  -- Very fast attack
        swing_radius = 25,      -- Short swing radius

        damage = 15,      -- Low damage
        range = 100,      -- Long reach
        knockback = 60,   -- Weak knockback

        hit_start = 0.2,
        hit_end = 0.6
    }
}

-- Weapon effects (shared across all weapon types)
entity_types.weapon_effects = {
    slash_sprite = "assets/images/effect-slash.png"
}

return entity_types

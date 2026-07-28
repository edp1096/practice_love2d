-- game/data/entities/humans/erratic.lua
-- Erratic entities with unpredictable behavior patterns
-- These characters have irregular AI logic and can suddenly change states

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
    -- Enemy definitions (can transform to NPC)
    enemies = {
        deceiver = {
            sprite_sheet = "assets/images/sprites/enemies/deceiver-sheet.png",
            health = 100,
            damage = 12,
            speed = 110,
            attack_cooldown = 1.0,
            detection_range = 280,
            attack_range = 35,
            loot_category = "deceiver",

            sprite_width = 48,
            sprite_height = 48,
            sprite_scale = 2,
            character_width = 16,
            character_height = 32,

            -- collider_width auto-calculated: 16 * 2 = 32
            -- collider_height auto-calculated: 32 * 2 = 64
            collider_offset_x = 0,
            collider_offset_y = 0,


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
    },

    -- NPC definitions (can transform to enemy or be transformed from enemy)
    npcs = {
        surrendered_bandit = {
            name = "Surrendered Bandit",
            sprite_sheet = "assets/images/sprites/enemies/enemy-sheet-human.png",
            dialogue_id = "surrendered_bandit", -- References game/data/dialogues.lua
            interaction_range = 80,

            sprite_width = 48,
            sprite_height = 48,
            sprite_scale = 2,
            character_width = 16,
            character_height = 32,

            -- collider auto-calculated

            collider_offset_x = 0,
            collider_offset_y = 0,

            sprite_origin_x = 24,
            sprite_origin_y = 24,

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
            sprite_sheet = "assets/images/sprites/enemies/deceiver-sheet.png",
            dialogue_id = "deceiver_greeting", -- References game/data/dialogues.lua
            interaction_range = 80,

            sprite_width = 48,
            sprite_height = 48,
            sprite_scale = 2,
            character_width = 16,
            character_height = 32,

            -- collider auto-calculated

            collider_offset_x = 0,
            collider_offset_y = 0,

            sprite_origin_x = 24,
            sprite_origin_y = 24,

            idle_down = "1-4",
            idle_left = "1-4",
            idle_right = "5-8",
            idle_up = "5-8",
            idle_row_down = 1,
            idle_row_left = 2,
            idle_row_right = 2,
            idle_row_up = 1,
        },
    },
}

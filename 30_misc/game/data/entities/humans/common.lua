-- game/data/entities/humans/common.lua
-- Common friendly NPCs (merchants, villagers, guards)

return {
    merchant = {
        name = "Merchant",
        sprite_sheet = "assets/images/sprites/npcs/npc-merchant_01-sheet.png",
        dialogue_id = "merchant_greeting",  -- References game/data/dialogues.lua
        interaction_range = 80,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 2,
        character_width = 16,
        character_height = 32,

        -- Auto-calculated: collider 32x64, offsets based on character/sprite size
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

    guard = {
        name = "Guard",
        sprite_sheet = "assets/images/player/player-sheet.png",
        dialogue = {
            "Hello player!",
        },
        interaction_range = 70,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 2,
        character_width = 16,
        character_height = 32,

        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

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
        sprite_sheet = "assets/images/sprites/npcs/npc-passerby_01-sheet.png",
        -- Use dialogue tree instead of simple dialogue array
        dialogue_id = "villager_greeting",  -- References game/data/dialogues.lua
        interaction_range = 80,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 2,
        character_width = 16,
        character_height = 32,

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

    elder = {
        name = "Village Elder",
        sprite_sheet = "assets/images/player/player-sheet.png",
        dialogue = {
            "Hello player!",
        },
        interaction_range = 90,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 2,
        character_width = 16,
        character_height = 32,

        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_origin_x = 24,
        sprite_origin_y = 24,

        idle_down = "1-4",
        idle_left = "1-4",
        idle_right = "5-8",
        idle_up = "5-8",
        idle_row_down = 3,
        idle_row_left = 4,
        idle_row_right = 5,
        idle_row_up = 4,
    },
}

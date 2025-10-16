-- entities/npc/types/villager.lua
-- NPC type configurations

local villager = {}

villager.NPC_TYPES = {
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
        collider_offset_x = 0,
        collider_offset_y = 8,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

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
        collider_offset_x = 0,
        collider_offset_y = 8,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

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
        dialogue = {
            "Hello player!",
            "Good bye player!",
        },
        interaction_range = 80,

        sprite_width = 48,
        sprite_height = 48,
        sprite_scale = 3,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 8,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

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
        collider_offset_x = 0,
        collider_offset_y = 8,

        sprite_draw_offset_x = -72,
        sprite_draw_offset_y = -144,

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

return villager

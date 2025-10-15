-- entities/npc/types/villager.lua
-- NPC type configurations

local villager = {}

villager.NPC_TYPES = {
    merchant = {
        name = "Merchant",
        sprite_sheet = "assets/images/player-sheet.png", -- Placeholder: use player sprite
        dialogue = {
            "Welcome to my shop!",
            "I have the finest wares in town.",
            "Come back anytime!"
        },
        interaction_range = 80,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -128,

        idle_frames = "1-1", -- First frame only
    },

    guard = {
        name = "Guard",
        sprite_sheet = "assets/images/player-sheet.png", -- Placeholder
        dialogue = {
            "Halt! State your business.",
            "Move along, citizen.",
        },
        interaction_range = 70,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -128,

        idle_frames = "1-1",
    },

    villager = {
        name = "Villager",
        sprite_sheet = "assets/images/player-sheet.png", -- Placeholder
        dialogue = {
            "Hello there!",
            "Nice day, isn't it?",
            "Have you seen my chickens?",
        },
        interaction_range = 80,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -128,

        idle_frames = "1-1",
    },

    elder = {
        name = "Village Elder",
        sprite_sheet = "assets/images/player-sheet.png", -- Placeholder
        dialogue = {
            "Young one, I have much wisdom to share.",
            "Listen well to my words.",
            "May fortune smile upon you.",
        },
        interaction_range = 90,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -128,

        idle_frames = "1-1",
    },
}

return villager

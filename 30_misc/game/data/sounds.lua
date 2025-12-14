-- data/sounds.lua

return {
    -- Sound variation presets
    variations = {
        pitch = {
            none = { min = 1.0, max = 1.0 },
            subtle = { min = 0.95, max = 1.05 },
            normal = { min = 0.9, max = 1.1 },
            wide = { min = 0.8, max = 1.2 },
            footstep = { min = 0.9, max = 1.1 },
            impact = { min = 0.85, max = 1.15 },
            voice = { min = 0.9, max = 1.2 }
        }
    },

    -- Category constants (prevent typos)
    categories = {
        PLAYER = "player",
        ENEMY = "enemy",
        COMBAT = "combat",
        MENU = "menu",
        UI = "ui",
        ITEM = "item"
    },

    bgm = {
        menu = { path = "assets/bgm/menu.ogg", volume = 0.7, loop = true },
        level1 = { path = "assets/bgm/level1.ogg", volume = 0.7, loop = true },
        level2 = { path = "assets/bgm/level2.mp3", volume = 0.7, loop = true },
        boss = { path = "assets/bgm/boss.ogg", volume = 0.8, loop = true },
        victory = { path = "assets/bgm/victory.mp3", volume = 0.8, loop = true },
        gameover = { path = "assets/bgm/gameover.ogg", volume = 0.8, loop = true },
        intro_level1 = { path = "assets/bgm/intro_level1.ogg", volume = 0.7, loop = true },
        intro_level2 = { path = "assets/bgm/intro_level2.ogg", volume = 0.7, loop = true },
        ending = { path = "assets/bgm/ending.mp3", volume = 0.8, loop = false },
    },

    sfx = {
        menu = {
            navigate = { path = "assets/sound/menu/navigate.wav", volume = 0.8, pitch_variation = "subtle" },
            select = { path = "assets/sound/menu/select.wav", volume = 0.9, pitch_variation = "subtle" },
            back = { path = "assets/sound/menu/back.wav", volume = 0.8, pitch_variation = "subtle" },
            error = { path = "assets/sound/menu/error.wav", volume = 0.7, pitch_variation = "none" }
        },

        ui = {
            save = { path = "assets/sound/ui/save.wav", volume = 0.8, pitch_variation = "none" },
            pause = { path = "assets/sound/ui/pause.wav", volume = 0.7, pitch_variation = "none" },
            unpause = { path = "assets/sound/ui/unpause.wav", volume = 0.7, pitch_variation = "none" },
            dialogue_typing = { path = "assets/sound/ui/dialogue_typing.wav", volume = 0.4, pitch_variation = "subtle" }
        },

        item = {
            -- Temporary: Use menu select sound for pickup/eat
            pickup = { path = "assets/sound/menu/select.wav", volume = 0.6, pitch_variation = "subtle" },
            eat = { path = "assets/sound/menu/select.wav", volume = 0.7, pitch_variation = "normal" }
        },

        combat = {
            hit_flesh = { path = "assets/sound/combat/hit_flesh.wav", volume = 0.8, pitch_variation = "normal" },
            hit_metal = { path = "assets/sound/combat/hit_metal.wav", volume = 0.9, pitch_variation = "normal" },
            parry = { path = "assets/sound/combat/parry.wav", volume = 0.9, pitch_variation = "subtle" },
            parry_perfect = { path = "assets/sound/combat/parry_perfect.wav", volume = 1.0, pitch_variation = "none" },
            death = { path = "assets/sound/combat/death.wav", volume = 0.8, pitch_variation = "wide" },

            sword_swing = { path = "assets/sound/player/sword_swing.wav", volume = 0.7, pitch_variation = "normal" },
            sword_hit = { path = "assets/sound/player/sword_hit.wav", volume = 0.8, pitch_variation = "impact" },
            dodge = { path = "assets/sound/player/dodge.wav", volume = 0.6, pitch_variation = "normal" },
            player_hurt = { path = "assets/sound/player/hurt.wav", volume = 0.8, pitch_variation = "wide" },
            weapon_draw = { path = "assets/sound/player/weapon_draw.wav", volume = 0.5, pitch_variation = "none" },
            weapon_sheath = { path = "assets/sound/player/weapon_sheath.wav", volume = 0.4, pitch_variation = "none" },

            slime_attack = { path = "assets/sound/enemy/slime_attack.wav", volume = 0.6, pitch_variation = "normal" },
            slime_hurt = { path = "assets/sound/enemy/slime_hurt.wav", volume = 0.7, pitch_variation = "wide" },
            slime_death = { path = "assets/sound/enemy/slime_death.wav", volume = 0.8, pitch_variation = "wide" },
            slime_stunned = { path = "assets/sound/enemy/slime_stunned.wav", volume = 0.6, pitch_variation = "none" },
            enemy_detect = { path = "assets/sound/enemy/detect.wav", volume = 0.5, pitch_variation = "subtle" }
        }
    },

    pools = {
        player = {
            footstep = { path = "assets/sound/player/footstep.wav", size = 4, volume = 0.3, pitch_variation = "footstep" }
        },
        enemy = {
            slime_move = { path = "assets/sound/enemy/slime_move.wav", size = 3, volume = 0.2, pitch_variation = "normal" }
        },
    },

    -- Enemy type sound mappings (maps enemy_type to sound names)
    enemy_sounds = {
        -- Slime enemies (matches any enemy type containing "slime")
        slime = {
            move = "slime_move",      -- Pooled sound
            attack = "slime_attack",  -- SFX
            hurt = "slime_hurt",      -- SFX
            death = "slime_death",    -- SFX
            stunned = "slime_stunned" -- SFX
        },
        -- Add more enemy types here as needed
        -- example:
        -- goblin = {
        --     move = "goblin_move",
        --     attack = "goblin_attack",
        --     hurt = "goblin_hurt",
        --     death = "goblin_death",
        --     stunned = "goblin_stunned"
        -- }
    },

    -- Vehicle sounds (managed by engine/entities/vehicle/sound.lua)
    -- NOT played via sound:playSFX - vehicle module handles looping/state transitions
    vehicle = {
        summon = { path = "assets/sound/vehicle/summon.wav", volume = 0.7 },
        board = { path = "assets/sound/vehicle/board.wav", volume = 0.6 },
        dismount = { path = "assets/sound/vehicle/dismount.wav", volume = 0.5 },
        engine_idle = { path = "assets/sound/vehicle/engine_idle.wav", volume = 0.4 },
        engine_start = { path = "assets/sound/vehicle/engine_start.wav", volume = 0.6 },
        engine_drive = { path = "assets/sound/vehicle/engine_drive.wav", volume = 0.5 }
    }
}

-- data/sounds.lua
-- Centralized sound definitions for easy management and modification

return {
    -- Background music tracks
    bgm = {
        menu = { path = "assets/bgm/menu.ogg", volume = 0.7, loop = true },
        level1 = { path = "assets/bgm/level1.ogg", volume = 0.7, loop = true },
        level2 = { path = "assets/bgm/level2.ogg", volume = 0.7, loop = true },
        boss = { path = "assets/bgm/boss.ogg", volume = 0.8, loop = true }
    },

    -- Sound effects organized by category
    sfx = {
        -- Menu and UI sounds
        menu = {
            navigate = { path = "assets/sound/menu/navigate.wav", volume = 0.8 },
            select = { path = "assets/sound/menu/select.wav", volume = 0.9 },
            back = { path = "assets/sound/menu/back.wav", volume = 0.8 },
            error = { path = "assets/sound/menu/error.wav", volume = 0.7 }
        },

        -- UI feedback sounds
        ui = {
            save = { path = "assets/sound/ui/save.wav", volume = 0.8 },
            pause = { path = "assets/sound/ui/pause.wav", volume = 0.7 },
            unpause = { path = "assets/sound/ui/unpause.wav", volume = 0.7 }
        },

        -- Combat sounds (shared between player and enemies)
        combat = {
            hit_flesh = { path = "assets/sound/combat/hit_flesh.wav", volume = 0.8 },
            hit_metal = { path = "assets/sound/combat/hit_metal.wav", volume = 0.9 },
            parry = { path = "assets/sound/combat/parry.wav", volume = 0.9 },
            parry_perfect = { path = "assets/sound/combat/parry_perfect.wav", volume = 1.0 },
            death = { path = "assets/sound/combat/death.wav", volume = 0.8 },

            -- Player-specific combat sounds
            sword_swing = { path = "assets/sound/player/sword_swing.wav", volume = 0.7 },
            sword_hit = { path = "assets/sound/player/sword_hit.wav", volume = 0.8 },
            dodge = { path = "assets/sound/player/dodge.wav", volume = 0.6 },
            player_hurt = { path = "assets/sound/player/hurt.wav", volume = 0.8 },
            weapon_draw = { path = "assets/sound/player/weapon_draw.wav", volume = 0.5 },
            weapon_sheath = { path = "assets/sound/player/weapon_sheath.wav", volume = 0.4 },

            -- Enemy combat sounds
            slime_attack = { path = "assets/sound/enemy/slime_attack.wav", volume = 0.6 },
            slime_hurt = { path = "assets/sound/enemy/slime_hurt.wav", volume = 0.7 },
            slime_death = { path = "assets/sound/enemy/slime_death.wav", volume = 0.8 },
            slime_stunned = { path = "assets/sound/enemy/slime_stunned.wav", volume = 0.6 },
            enemy_detect = { path = "assets/sound/enemy/detect.wav", volume = 0.5 }
        }
    },

    -- Sound pools for frequently played sounds (better performance)
    pools = {
        player = {
            footstep = { path = "assets/sound/player/footstep.wav", size = 4, volume = 0.3 }
        },
        enemy = {
            slime_move = { path = "assets/sound/enemy/slime_move.wav", size = 3, volume = 0.2 }
        }
    }
}

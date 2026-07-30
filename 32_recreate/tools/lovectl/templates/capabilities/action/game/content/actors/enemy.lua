return {
    schema_version = 1,
    kind = "actor",
    id = "actor.enemy",
    name = "Training Enemy",
    tags = {"enemy"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 14,
            solid = true,
        },
        ["render.shape"] = {
            shape = "circle",
            radius = 14,
            color = {0.9, 0.28, 0.25, 1},
            outline = {1, 0.7, 0.6, 1},
            label = "ENEMY",
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["movement.topdown"] = {speed = 75},
        ["action.hurtbox"] = {radius = 14},
        ["action.health"] = {
            max = 60,
            death_delay = 0.3,
        },
        ["action.reaction"] = {
            hit_invulnerability = 0.1,
            flash_duration = 0.16,
        },
        ["action.status"] = {},
        ["action.knockback"] = {resistance = 0},
        ["action.combat"] = {
            team = "enemy",
            abilities = {"ability.enemy_strike"},
            primary = "ability.enemy_strike",
        },
        ["action.behavior_ai"] = {
            target_tag = "player",
            aggro_range = 300,
            patterns = {
                {
                    id = "primary",
                    movement = {
                        minimum_range = 0,
                        preferred_range = 36,
                    },
                    attacks = {
                        {
                            ability = "ability.enemy_strike",
                            maximum_range = 36,
                        },
                    },
                },
            },
        },
    },
}

return {
    schema_version = 1,
    kind = "actor",
    id = "actor.grove_guardian",
    name = "Grove Guardian",
    tags = {"enemy", "boss"},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 20,
            solid = true,
        },
        ["action.hurtbox"] = {
            radius = 20,
        },
        ["render.sprite"] = {
            sprite = "sprite.slime",
            scale = 4,
            tint = {0.76, 0.42, 1.0, 1.0},
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["movement.topdown"] = {
            speed = 64,
        },
        ["action.health"] = {
            max = 240,
            death_delay = 0.55,
        },
        ["action.reaction"] = {
            hit_invulnerability = 0.1,
            flash_duration = 0.18,
        },
        ["action.status"] = {},
        ["action.knockback"] = {
            resistance = 0.65,
        },
        ["action.combat"] = {
            team = "enemy",
            abilities = {
                "ability.slime_bump",
                "ability.fire_bolt",
                "ability.whirlwind",
            },
            primary = "ability.slime_bump",
        },
        ["action.behavior_ai"] = {
            target_tag = "player",
            aggro_range = 520,
            patterns = {
                {
                    id = "sentinel",
                    movement = {
                        minimum_range = 0,
                        preferred_range = 44,
                    },
                    attacks = {
                        {
                            ability = "ability.slime_bump",
                            maximum_range = 44,
                        },
                    },
                },
                {
                    id = "awakened",
                    health_ratio_at_most = 0.5,
                    movement = {
                        minimum_range = 88,
                        preferred_range = 156,
                        orbit = true,
                    },
                    attacks = {
                        {
                            ability = "ability.fire_bolt",
                            minimum_range = 72,
                            maximum_range = 320,
                        },
                        {
                            ability = "ability.whirlwind",
                            maximum_range = 56,
                        },
                    },
                },
            },
        },
    },
}

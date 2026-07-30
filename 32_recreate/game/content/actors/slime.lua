return {
    schema_version = 1,
    kind = "actor",
    id = "actor.slime",
    name = "Slime",
    tags = {"enemy"},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 13,
            solid = true,
        },
        ["action.hurtbox"] = {
            radius = 13,
        },
        ["render.sprite"] = {
            sprite = "sprite.slime",
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["movement.topdown"] = {
            speed = 72,
        },
        ["action.health"] = {
            max = 68,
            death_delay = 0.35,
        },
        ["action.reaction"] = {
            hit_invulnerability = 0.12,
            flash_duration = 0.16,
        },
        ["action.status"] = {},
        ["action.knockback"] = {
            resistance = 0,
        },
        ["action.combat"] = {
            team = "enemy",
            abilities = {"ability.slime_bump"},
            primary = "ability.slime_bump",
        },
        ["action.behavior_ai"] = {
            target_tag = "player",
            aggro_range = 360,
            patterns = {
                {
                    id = "bump",
                    movement = {
                        minimum_range = 0,
                        preferred_range = 38,
                    },
                    attacks = {
                        {
                            ability = "ability.slime_bump",
                            maximum_range = 38,
                        },
                    },
                },
            },
        },
    },
}

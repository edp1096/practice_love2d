return {
    schema_version = 1,
    kind = "actor",
    id = "actor.runner",
    name = "Runner",
    tags = {"player"},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 15,
            solid = true,
        },
        ["action.hurtbox"] = {
            radius = 15,
        },
        ["render.sprite"] = {
            sprite = "sprite.hero",
        },
        ["motion.facing"] = {
            x = 1,
            y = 0,
        },
        ["motion.kinematics"] = {},
        ["movement.platformer"] = {
            speed = 220,
            acceleration = 1500,
            air_acceleration = 900,
            deceleration = 1800,
            gravity = 1500,
            jump_speed = 600,
            max_fall_speed = 900,
            coyote_time = 0.1,
            jump_buffer = 0.1,
        },
        ["control.player"] = {},
        ["action.health"] = {
            max = 100,
            remove_on_death = false,
        },
        ["action.reaction"] = {
            hit_invulnerability = 0.35,
            flash_duration = 0.18,
        },
        ["action.status"] = {},
        ["action.knockback"] = {
            resistance = 0.15,
        },
        ["action.combat"] = {
            team = "player",
            abilities = {
                "ability.sword_slash",
                "ability.fire_bolt",
                "ability.whirlwind",
            },
            primary = "ability.sword_slash",
        },
        ["action.combat_input"] = {
            bindings = {
                {
                    input = "attack",
                    ability = "ability.sword_slash",
                },
                {
                    input = "special",
                    ability = "ability.fire_bolt",
                },
                {
                    input = "technique",
                    ability = "ability.whirlwind",
                },
            },
        },
    },
}

return {
    schema_version = 1,
    kind = "actor",
    id = "actor.hero",
    name = "Hero",
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
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["movement.topdown"] = {
            speed = 190,
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
        ["action.dodge"] = {
            input = "dodge",
            duration = 0.22,
            distance = 78,
            invulnerability = 0.18,
            cooldown = 0.48,
        },
        ["action.parry"] = {
            input = "parry",
            window = 0.32,
            perfect_window = 0.12,
            cooldown = 0.75,
            success_cooldown = 0.18,
            arc_degrees = 170,
            stagger = 0.55,
            perfect_stagger = 1.1,
            hitstop = 0.035,
            perfect_hitstop = 0.06,
        },
        ["rpg.stats"] = {
            attack = 0,
            defense = 0,
            move_speed = 1,
        },
        ["rpg.equipment"] = {
            loadout = "hero",
            slots = {"weapon", "armor", "accessory"},
        },
    },
}

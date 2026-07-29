return {
    schema_version = 1,
    kind = "actor",
    id = "actor.player",
    name = "Player",
    tags = {"player"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 15,
            solid = true,
        },
        ["render.shape"] = {
            shape = "circle",
            radius = 15,
            color = {0.22, 0.82, 0.52, 1},
            outline = {0.75, 1, 0.86, 1},
            label = "PLAYER",
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["movement.topdown"] = {speed = 180},
        ["control.player"] = {},
        ["action.hurtbox"] = {radius = 15},
        ["action.health"] = {
            max = 100,
            remove_on_death = false,
        },
        ["action.reaction"] = {
            hit_invulnerability = 0.3,
            flash_duration = 0.16,
        },
        ["action.status"] = {},
        ["action.knockback"] = {resistance = 0.15},
        ["action.combat"] = {
            team = "player",
            abilities = {"ability.slash", "ability.bolt"},
            primary = "ability.slash",
        },
        ["action.combat_input"] = {
            bindings = {
                {input = "attack", ability = "ability.slash"},
                {input = "special", ability = "ability.bolt"},
            },
        },
        ["action.dodge"] = {
            input = "dodge",
            duration = 0.22,
            distance = 76,
            invulnerability = 0.18,
            cooldown = 0.48,
        },
        ["action.parry"] = {
            input = "parry",
            window = 0.3,
            perfect_window = 0.1,
            cooldown = 0.7,
        },
        ["rpg.stats"] = {
            attack = 0,
            defense = 0,
            move_speed = 1,
        },
        ["rpg.equipment"] = {
            loadout = "player",
            slots = {"weapon", "armor", "accessory"},
        },
    },
}

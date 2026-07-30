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
        ["action.health"] = {
            max = 100,
            remove_on_death = false,
        },
        ["rpg.stats"] = {
            attack = 2,
            defense = 1,
            move_speed = 1,
        },
        ["rpg.turn_battler"] = {
            skills = {
                "turn_skill.strike",
                "turn_skill.mend",
            },
        },
        ["rpg.equipment"] = {
            loadout = "player",
            slots = {"weapon", "armor", "accessory"},
        },
    },
}

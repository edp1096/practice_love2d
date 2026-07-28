return {
    schema_version = 1,
    kind = "stage",
    id = "stage.action_room",
    name = "Action Runtime Vertical Slice",

    width = 960,
    height = 540,
    background = {0.07, 0.085, 0.12, 1.0},

    spawns = {
        {
            id = "player",
            actor = "actor.hero",
            position = {x = 180, y = 270},
        },
        {
            id = "enemy.slime.1",
            actor = "actor.slime",
            position = {x = 560, y = 190},
        },
        {
            id = "enemy.slime.2",
            actor = "actor.slime",
            position = {x = 660, y = 350},
        },
        {
            id = "wall.center",
            actor = "actor.wall",
            position = {x = 460, y = 270},
            components = {
                body = {
                    width = 76,
                    height = 180,
                },
                ["render.shape"] = {
                    label = "WALL",
                },
            },
        },
        {
            id = "wall.upper",
            actor = "actor.wall",
            position = {x = 300, y = 120},
            components = {
                body = {
                    width = 160,
                    height = 42,
                },
            },
        },
    },
}

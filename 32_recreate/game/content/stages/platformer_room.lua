return {
    schema_version = 1,
    kind = "stage",
    id = "stage.platformer_room",
    name = "Independent Platformer Movement Slice",
    mode = "platformer",

    width = 960,
    height = 540,
    background = {0.045, 0.075, 0.12, 1.0},
    camera = {
        viewport_width = 800,
        viewport_height = 450,
        follow_tag = "player",
    },

    spawns = {
        {
            id = "player",
            actor = "actor.runner",
            position = {x = 360, y = 485},
        },
        {
            id = "visual.floor",
            actor = "actor.wall",
            position = {x = 480, y = 520},
            components = {
                body = {
                    width = 960,
                    height = 40,
                    solid = false,
                },
                ["render.shape"] = {
                    color = {0.16, 0.25, 0.35, 1.0},
                    outline = {0.3, 0.65, 0.85, 1.0},
                },
            },
        },
        {
            id = "visual.raised_platform",
            actor = "actor.wall",
            position = {x = 520, y = 402},
            components = {
                body = {
                    width = 180,
                    height = 24,
                    solid = false,
                },
                ["render.shape"] = {
                    color = {0.2, 0.36, 0.42, 1.0},
                    outline = {0.35, 0.85, 0.72, 1.0},
                },
            },
        },
    },
    walls = {
        {
            id = "floor",
            shape = {
                type = "rectangle",
                x = 480,
                y = 520,
                width = 960,
                height = 40,
            },
        },
        {
            id = "raised_platform",
            shape = {
                type = "rectangle",
                x = 520,
                y = 402,
                width = 180,
                height = 24,
            },
        },
    },
}

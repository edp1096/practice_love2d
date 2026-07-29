return {
    schema_version = 1,
    kind = "stage",
    id = "stage.start",
    name = "RPG Starter",
    width = 960,
    height = 540,
    background = {0.07, 0.1, 0.085, 1},
    camera = {
        viewport_width = 960,
        viewport_height = 540,
        follow_tag = "player",
    },
    spawns = {
        {
            id = "player",
            actor = "actor.player",
            position = {x = 180, y = 270},
        },
        {
            id = "guide",
            actor = "actor.guide",
            position = {x = 300, y = 230},
        },
        {
            id = "merchant",
            actor = "actor.merchant",
            position = {x = 500, y = 310},
        },
    },
}

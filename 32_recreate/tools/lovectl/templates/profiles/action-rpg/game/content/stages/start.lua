return {
    schema_version = 1,
    kind = "stage",
    id = "stage.start",
    name = "Action RPG Starter",
    width = 960,
    height = 540,
    background = {0.075, 0.075, 0.105, 1},
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
            id = "enemy",
            actor = "actor.enemy",
            position = {x = 520, y = 210},
        },
        {
            id = "guide",
            actor = "actor.guide",
            position = {x = 330, y = 350},
        },
        {
            id = "merchant",
            actor = "actor.merchant",
            position = {x = 650, y = 350},
        },
    },
}

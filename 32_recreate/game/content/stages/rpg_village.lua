return {
    schema_version = 1,
    kind = "stage",
    id = "stage.rpg_village",
    name = "RPG Vertical Slice Village",

    width = 960,
    height = 540,
    background = {0.055, 0.11, 0.09, 1.0},
    camera = {
        viewport_width = 800,
        viewport_height = 450,
        follow_tag = "player",
    },

    spawns = {
        {
            id = "player",
            actor = "actor.hero",
            position = {x = 150, y = 270},
        },
        {
            id = "guide",
            actor = "actor.guide",
            position = {x = 260, y = 240},
        },
        {
            id = "merchant",
            actor = "actor.merchant",
            position = {x = 390, y = 240},
        },
        {
            id = "quest.slime.1",
            actor = "actor.slime",
            position = {x = 620, y = 215},
        },
        {
            id = "quest.slime.2",
            actor = "actor.slime",
            position = {x = 700, y = 325},
        },
    },
    spawn_points = {
        {
            id = "default",
            x = 150,
            y = 270,
        },
        {
            id = "field_return",
            x = 850,
            y = 270,
        },
    },
    portals = {
        {
            id = "to_field",
            shape = {
                type = "rectangle",
                x = 944,
                y = 270,
                width = 32,
                height = 128,
            },
            target_stage = "stage.world_hub",
            target_spawn = "village_entry",
        },
    },
    walls = {
        {
            id = "north",
            shape = {
                type = "rectangle",
                x = 480,
                y = 16,
                width = 960,
                height = 32,
            },
        },
        {
            id = "south",
            shape = {
                type = "rectangle",
                x = 480,
                y = 524,
                width = 960,
                height = 32,
            },
        },
        {
            id = "west",
            shape = {
                type = "rectangle",
                x = 16,
                y = 270,
                width = 32,
                height = 540,
            },
        },
        {
            id = "east_north",
            shape = {
                type = "rectangle",
                x = 944,
                y = 103,
                width = 32,
                height = 206,
            },
        },
        {
            id = "east_south",
            shape = {
                type = "rectangle",
                x = 944,
                y = 437,
                width = 32,
                height = 206,
            },
        },
    },
}

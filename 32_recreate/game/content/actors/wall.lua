return {
    schema_version = 1,
    kind = "actor",
    id = "actor.wall",
    name = "Wall",
    tags = {"wall"},

    components = {
        transform = {},
        body = {
            shape = "rectangle",
            width = 64,
            height = 64,
            static = true,
            solid = true,
        },
        ["render.shape"] = {
            shape = "rectangle",
            color = {0.25, 0.27, 0.34, 1.0},
            outline = {0.4, 0.44, 0.56, 1.0},
            layer = 0,
        },
    },
}

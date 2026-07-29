return {
    schema_version = 1,
    kind = "actor",
    id = "actor.bolt",
    name = "Bolt",
    tags = {"projectile"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 5,
            solid = true,
            collision_layer = "projectile",
            collision_mask = {"world"},
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["render.shape"] = {
            shape = "circle",
            radius = 6,
            color = {0.25, 0.75, 1, 1},
            outline = {0.8, 0.95, 1, 1},
            layer = 10,
        },
    },
}

return {
    schema_version = 1,
    kind = "actor",
    id = "actor.fire_bolt",
    name = "Fire Bolt",
    tags = {"projectile"},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 6,
            solid = true,
            collision_layer = "projectile",
            collision_mask = {"world"},
        },
        ["motion.facing"] = {},
        ["motion.kinematics"] = {},
        ["render.shape"] = {
            shape = "circle",
            radius = 7,
            color = {0.2, 0.85, 1.0, 0.95},
            outline = {0.75, 0.98, 1.0, 1.0},
            layer = 10,
        },
    },
}

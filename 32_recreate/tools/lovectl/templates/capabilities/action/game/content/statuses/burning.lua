return {
    schema_version = 1,
    kind = "status",
    id = "status.burning",
    name = "Burning",
    duration = 1.2,
    stacking = "refresh",
    tick_interval = 0.4,
    tick_actions = {
        {type = "damage", amount = 2},
    },
    modifiers = {
        move_speed = 0.9,
    },
    color = {1, 0.35, 0.08, 1},
}

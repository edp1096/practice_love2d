return {
    schema_version = 1,
    kind = "status",
    id = "status.burning",
    name = "Burning",

    duration = 1.5,
    stacking = "stack",
    max_stacks = 3,
    tick_interval = 0.5,
    tick_actions = {
        {
            type = "damage",
            amount = 3,
        },
    },
    modifiers = {
        move_speed = 0.85,
    },
    color = {1.0, 0.35, 0.08, 1.0},
}

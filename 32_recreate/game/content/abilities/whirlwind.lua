return {
    schema_version = 1,
    kind = "ability",
    id = "ability.whirlwind",
    name = "Whirlwind",

    hitbox = {
        shape = "arc",
        reach = 42,
        arc_degrees = 360,
        repeat_interval = 0.15,
        max_hits = 3,
    },
    cooldown = 1.1,
    windup = 0.1,
    duration = 0.42,
    recovery = 0.2,
    lock_movement = true,

    effects = {
        {
            type = "damage",
            amount = 6,
        },
        {
            type = "stagger",
            duration = 0.04,
        },
        {
            type = "hitstop",
            duration = 0.012,
        },
    },
}

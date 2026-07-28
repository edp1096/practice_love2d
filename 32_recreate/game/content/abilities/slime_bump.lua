return {
    schema_version = 1,
    kind = "ability",
    id = "ability.slime_bump",
    name = "Slime Bump",

    hitbox = {
        shape = "arc",
        reach = 10,
        arc_degrees = 180,
    },
    cooldown = 0.85,
    windup = 0.35,
    duration = 0.1,
    recovery = 0.16,
    lock_movement = true,

    effects = {
        {
            type = "damage",
            amount = 8,
        },
        {
            type = "stagger",
            duration = 0.18,
        },
        {
            type = "knockback",
            distance = 18,
            duration = 0.1,
        },
        {
            type = "hitstop",
            duration = 0.04,
        },
    },
}

return {
    schema_version = 1,
    kind = "ability",
    id = "ability.sword_slash",
    name = "Sword Slash",

    hitbox = {
        shape = "arc",
        reach = 48,
        arc_degrees = 105,
    },
    cooldown = 0.28,
    windup = 0,
    duration = 0.12,
    recovery = 0.14,
    lock_movement = true,

    visual = {
        asset = "image.slash",
        scale = 1.2,
        distance = 31,
    },

    effects = {
        {
            type = "damage",
            amount = 34,
        },
        {
            type = "stagger",
            duration = 0.22,
        },
        {
            type = "knockback",
            distance = 24,
            duration = 0.12,
        },
        {
            type = "hitstop",
            duration = 0.05,
        },
    },
}

return {
    schema_version = 1,
    kind = "ability",
    id = "ability.slash",
    name = "Slash",
    hitbox = {
        shape = "arc",
        reach = 46,
        arc_degrees = 110,
    },
    cooldown = 0.3,
    windup = 0,
    duration = 0.12,
    recovery = 0.14,
    lock_movement = true,
    effects = {
        {type = "damage", amount = 20},
        {type = "stagger", duration = 0.2},
        {type = "knockback", distance = 18, duration = 0.1},
        {type = "hitstop", duration = 0.035},
    },
}

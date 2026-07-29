return {
    schema_version = 1,
    kind = "ability",
    id = "ability.enemy_strike",
    name = "Enemy Strike",
    hitbox = {
        shape = "arc",
        reach = 34,
        arc_degrees = 120,
    },
    cooldown = 0.8,
    windup = 0.18,
    duration = 0.1,
    recovery = 0.2,
    effects = {
        {type = "damage", amount = 8},
        {type = "stagger", duration = 0.12},
    },
}

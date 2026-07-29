return {
    schema_version = 1,
    kind = "ability",
    id = "ability.bolt",
    name = "Bolt",
    cooldown = 0.55,
    windup = 0.08,
    duration = 0.05,
    recovery = 0.12,
    lock_movement = true,
    activation = {
        {type = "spawn_projectile", projectile = "projectile.bolt"},
    },
}

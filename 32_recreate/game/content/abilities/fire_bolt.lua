return {
    schema_version = 1,
    kind = "ability",
    id = "ability.fire_bolt",
    name = "Fire Bolt",

    cooldown = 0.5,
    windup = 0.12,
    duration = 0.04,
    recovery = 0.16,
    lock_movement = true,

    activation = {
        {
            type = "spawn_projectile",
            projectile = "projectile.fire_bolt",
        },
    },
}

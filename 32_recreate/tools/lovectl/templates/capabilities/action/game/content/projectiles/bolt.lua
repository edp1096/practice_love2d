return {
    schema_version = 1,
    kind = "projectile",
    id = "projectile.bolt",
    name = "Bolt",
    actor = "actor.bolt",
    speed = 420,
    lifetime = 1.5,
    spawn_offset = 24,
    pierce = 0,
    destroy_on_wall = true,
    effects = {
        {type = "damage", amount = 12},
        {type = "apply_status", status = "status.burning"},
    },
}

return {
    schema_version = 1,
    kind = "projectile",
    id = "projectile.fire_bolt",
    name = "Fire Bolt",
    actor = "actor.fire_bolt",

    speed = 420,
    lifetime = 1.8,
    spawn_offset = 25,
    pierce = 0,
    destroy_on_wall = true,

    effects = {
        {
            type = "damage",
            amount = 18,
        },
        {
            type = "stagger",
            duration = 0.12,
        },
        {
            type = "apply_status",
            status = "status.burning",
        },
        {
            type = "knockback",
            distance = 12,
            duration = 0.08,
        },
        {
            type = "hitstop",
            duration = 0.025,
        },
    },
}

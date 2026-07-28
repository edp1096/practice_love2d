return {
    schema_version = 1,
    kind = "encounter",
    id = "encounter.slime_trial",
    name = "Slime Trial",
    target_tag = "player",

    waves = {
        {
            id = "scouts",
            delay = 0.1,
            spawns = {
                {
                    id = "left",
                    actor = "actor.slime",
                    position = {x = -60, y = 190},
                },
                {
                    id = "right",
                    actor = "actor.slime",
                    position = {x = 80, y = 190},
                },
            },
            on_start = {
                {
                    type = "emit",
                    name = "encounter.scouts_started",
                },
            },
        },
        {
            id = "boss",
            delay = 0.15,
            spawns = {
                {
                    id = "champion",
                    actor = "actor.slime",
                    tags = {"boss"},
                    position = {x = 0, y = 190},
                    components = {
                        ["action.health"] = {
                            max = 120,
                        },
                        ["movement.topdown"] = {
                            speed = 86,
                        },
                    },
                },
            },
            boss_phases = {
                {
                    id = "enraged",
                    spawn = "champion",
                    health_ratio_at_most = 0.5,
                    actions = {
                        {
                            type = "apply_status",
                            status = "status.enraged",
                        },
                    },
                },
            },
        },
    },

    on_complete = {
        {
            type = "emit",
            name = "encounter.slime_trial_completed",
        },
    },
}

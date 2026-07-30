return {
    schema_version = 1,
    kind = "encounter",
    id = "encounter.training",
    name = "Training Encounter",
    target_tag = "player",
    waves = {
        {
            id = "wave_1",
            spawns = {
                {
                    id = "enemy",
                    actor = "actor.enemy",
                    position = {x = 0, y = 0},
                },
            },
        },
    },
    on_complete = {
        {type = "finish_game"},
    },
}

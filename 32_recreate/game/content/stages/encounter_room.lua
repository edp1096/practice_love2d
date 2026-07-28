return {
    schema_version = 1,
    kind = "stage",
    id = "stage.encounter_room",
    name = "Encounter and Boss Phase Slice",

    width = 960,
    height = 540,
    background = {0.09, 0.055, 0.09, 1.0},

    spawns = {
        {
            id = "player",
            actor = "actor.hero",
            position = {x = 180, y = 270},
        },
    },
    encounters = {
        {
            id = "arena",
            encounter = "encounter.slime_trial",
            position = {x = 480, y = 80},
            auto_start = true,
        },
    },
}

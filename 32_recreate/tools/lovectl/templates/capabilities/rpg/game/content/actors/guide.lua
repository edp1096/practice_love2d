return {
    schema_version = 1,
    kind = "actor",
    id = "actor.guide",
    name = "Guide",
    tags = {"npc"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 17,
            solid = false,
        },
        ["render.shape"] = {
            shape = "circle",
            radius = 17,
            color = {0.3, 0.68, 1, 1},
            outline = {0.8, 0.94, 1, 1},
            label = "GUIDE",
        },
        ["rpg.interactable"] = {
            input = "interact",
            range = 72,
            prompt_key = "interaction.talk",
            actions = {
                {
                    type = "set_flag",
                    name = "maker.smoke.interacted",
                },
                {
                    type = "start_quest",
                    quest = "quest.first_steps",
                },
                {
                    type = "start_dialogue",
                    dialogue = "dialogue.guide",
                },
            },
        },
    },
}

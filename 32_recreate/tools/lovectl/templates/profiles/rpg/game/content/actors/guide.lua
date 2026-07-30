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
            pages = {
                {
                    id = "before_quest",
                    prompt_key = "interaction.quest",
                    actions = {
                        {
                            type = "set_flag",
                            name = "maker.smoke.interacted",
                        },
                        {
                            type = "start_dialogue",
                            dialogue = "dialogue.guide",
                        },
                    },
                },
                {
                    id = "quest_active",
                    condition = {
                        type = "quest_state",
                        quest = "quest.first_steps",
                        state = "active",
                    },
                    prompt_key = "interaction.report",
                    actions = {
                        {
                            type = "set_flag",
                            name = "maker.smoke.interacted",
                        },
                        {
                            type = "start_dialogue",
                            dialogue = "dialogue.guide",
                        },
                    },
                },
                {
                    id = "quest_complete",
                    condition = {
                        type = "quest_state",
                        quest = "quest.first_steps",
                        state = "completed",
                    },
                    prompt_key = "interaction.thanks",
                    actions = {
                        {
                            type = "set_flag",
                            name = "maker.smoke.interacted",
                        },
                        {
                            type = "start_dialogue",
                            dialogue = "dialogue.guide",
                        },
                    },
                },
            },
        },
    },
}

return {
    schema_version = 1,
    kind = "actor",
    id = "actor.village_guide",
    name = "Village Guide",
    tags = {"npc", "guide"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 18,
            solid = false,
        },
        ["render.sprite"] = {
            sprite = "sprite.guide",
        },
        ["motion.facing"] = {},
        ["rpg.interactable"] = {
            input = "interact",
            range = 70,
            pages = {
                {
                    id = "before_quest",
                    prompt_key = "interaction.quest",
                    actions = {
                        {
                            type = "start_dialogue",
                            dialogue = "dialogue.village_guide",
                        },
                    },
                },
                {
                    id = "quest_active",
                    condition = {
                        type = "quest_state",
                        quest = "quest.grove_guardian",
                        state = "active",
                    },
                    prompt_key = "interaction.report",
                    actions = {
                        {
                            type = "start_dialogue",
                            dialogue = "dialogue.village_guide",
                        },
                    },
                },
                {
                    id = "quest_complete",
                    condition = {
                        type = "quest_state",
                        quest = "quest.grove_guardian",
                        state = "completed",
                    },
                    prompt_key = "interaction.thanks",
                    actions = {
                        {
                            type = "start_dialogue",
                            dialogue = "dialogue.village_guide",
                        },
                    },
                },
            },
        },
    },
}

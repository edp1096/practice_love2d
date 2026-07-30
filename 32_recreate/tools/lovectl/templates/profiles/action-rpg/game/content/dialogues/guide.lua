return {
    schema_version = 1,
    kind = "dialogue",
    id = "dialogue.guide",
    name_key = "dialogue.guide.name",
    start = "status",
    nodes = {
        status = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.start",
            choices = {
                {
                    id = "accept",
                    text_key = "dialogue.guide.accept_choice",
                    condition = {
                        type = "quest_state",
                        quest = "quest.first_steps",
                        state = "inactive",
                    },
                    actions = {
                        {
                            type = "start_quest",
                            quest = "quest.first_steps",
                        },
                    },
                    next = "accepted",
                },
                {
                    id = "progress",
                    text_key = "dialogue.guide.progress_choice",
                    condition = {
                        type = "quest_state",
                        quest = "quest.first_steps",
                        state = "active",
                    },
                    next = "progress",
                },
                {
                    id = "complete",
                    text_key = "dialogue.guide.complete_choice",
                    condition = {
                        type = "quest_state",
                        quest = "quest.first_steps",
                        state = "completed",
                    },
                    actions = {
                        {type = "finish_game"},
                    },
                },
            },
        },
        accepted = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.accept",
        },
        progress = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.progress",
        },
    },
}

return {
    schema_version = 1,
    kind = "dialogue",
    id = "dialogue.guide",
    name_key = "dialogue.guide.name",
    start = "greeting",
    nodes = {
        greeting = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.greeting",
            choices = {
                {
                    id = "accept",
                    text_key = "dialogue.guide.accept",
                    condition = {
                        type = "quest_state",
                        quest = "quest.slime_patrol",
                        state = "inactive",
                    },
                    actions = {
                        {
                            type = "start_quest",
                            quest = "quest.slime_patrol",
                        },
                        {
                            type = "give_item",
                            item = "item.training_sword",
                        },
                        {
                            type = "equip_item",
                            item = "item.training_sword",
                        },
                    },
                    next = "accepted",
                },
                {
                    id = "progress",
                    text_key = "dialogue.guide.progress",
                    condition = {
                        type = "quest_state",
                        quest = "quest.slime_patrol",
                        state = "active",
                    },
                    next = "reminder",
                },
                {
                    id = "completed",
                    text_key = "dialogue.guide.completed",
                    condition = {
                        type = "quest_state",
                        quest = "quest.slime_patrol",
                        state = "completed",
                    },
                    next = "thanks",
                },
                {
                    id = "leave",
                    text_key = "dialogue.guide.leave",
                },
            },
        },
        accepted = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.accepted",
        },
        reminder = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.reminder",
        },
        thanks = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.thanks",
        },
    },
}

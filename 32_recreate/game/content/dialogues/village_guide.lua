return {
    schema_version = 1,
    kind = "dialogue",
    id = "dialogue.village_guide",
    name_key = "dialogue.village_guide.name",
    start = "greeting",
    nodes = {
        greeting = {
            speaker_key = "npc.village_guide.name",
            text_key = "dialogue.village_guide.greeting",
            choices = {
                {
                    id = "accept",
                    text_key = "dialogue.village_guide.accept",
                    condition = {
                        type = "quest_state",
                        quest = "quest.grove_guardian",
                        state = "inactive",
                    },
                    actions = {
                        {
                            type = "start_quest",
                            quest = "quest.grove_guardian",
                        },
                        {
                            type = "give_item",
                            item = "item.training_sword",
                        },
                        {
                            type = "equip_item",
                            item = "item.training_sword",
                        },
                        {
                            type = "add_currency",
                            amount = 25,
                            reason = "campaign.starting_supplies",
                        },
                        {
                            type = "show_notice",
                            text_key = "notice.quest.accepted",
                            tone = "success",
                            duration = 4,
                        },
                    },
                    next = "accepted",
                },
                {
                    id = "progress",
                    text_key = "dialogue.village_guide.progress",
                    condition = {
                        type = "quest_state",
                        quest = "quest.grove_guardian",
                        state = "active",
                    },
                    next = "reminder",
                },
                {
                    id = "completed",
                    text_key = "dialogue.village_guide.completed",
                    condition = {
                        type = "quest_state",
                        quest = "quest.grove_guardian",
                        state = "completed",
                    },
                    next = "thanks",
                },
                {
                    id = "leave",
                    text_key = "dialogue.village_guide.leave",
                },
            },
        },
        accepted = {
            speaker_key = "npc.village_guide.name",
            text_key = "dialogue.village_guide.accepted",
        },
        reminder = {
            speaker_key = "npc.village_guide.name",
            text_key = "dialogue.village_guide.reminder",
        },
        thanks = {
            speaker_key = "npc.village_guide.name",
            text_key = "dialogue.village_guide.thanks",
            actions = {
                {
                    type = "finish_game",
                },
            },
        },
    },
}

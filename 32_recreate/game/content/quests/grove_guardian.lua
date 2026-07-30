return {
    schema_version = 1,
    kind = "quest",
    id = "quest.grove_guardian",
    name_key = "quest.grove_guardian.name",
    description_key = "quest.grove_guardian.description",
    objectives = {
        {
            id = "defeat_slimes",
            event = "actor.killed",
            count = 2,
            where = {
                actor_id = "actor.slime",
            },
        },
        {
            id = "defeat_guardian",
            event = "actor.killed",
            count = 1,
            where = {
                actor_id = "actor.grove_guardian",
            },
        },
    },
    on_complete = {
        {
            type = "give_item",
            item = "item.potion",
        },
        {
            type = "add_currency",
            amount = 75,
            reason = "quest.grove_guardian",
        },
        {
            type = "set_flag",
            name = "quest.grove_guardian.rewarded",
        },
        {
            type = "set_world_time",
            time = "18:30",
        },
        {
            type = "show_notice",
            text_key = "notice.quest.completed",
            tone = "success",
            duration = 4,
        },
    },
}

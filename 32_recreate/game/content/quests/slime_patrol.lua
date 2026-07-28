return {
    schema_version = 1,
    kind = "quest",
    id = "quest.slime_patrol",
    name_key = "quest.slime_patrol.name",
    description_key = "quest.slime_patrol.description",
    objectives = {
        {
            id = "defeat_slimes",
            event = "actor.killed",
            count = 2,
            where = {
                actor_id = "actor.slime",
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
            amount = 100,
            reason = "quest.slime_patrol",
        },
        {
            type = "set_flag",
            name = "quest.slime_patrol.rewarded",
        },
    },
}

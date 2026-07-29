return {
    schema_version = 1,
    kind = "quest",
    id = "quest.first_steps",
    name_key = "quest.first_steps.name",
    description_key = "quest.first_steps.description",
    objectives = {
        {
            id = "progress",
            event = "maker.quest.progress",
            count = 1,
        },
    },
    on_complete = {
        {type = "give_item", item = "item.potion"},
        {type = "add_currency", amount = 25, reason = "quest.first_steps"},
    },
}

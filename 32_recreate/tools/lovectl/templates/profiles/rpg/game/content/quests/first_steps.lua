return {
    schema_version = 1,
    kind = "quest",
    id = "quest.first_steps",
    name_key = "quest.first_steps.name",
    description_key = "quest.first_steps.description",
    objectives = {
        {
            id = "defeat_slime",
            event = "turn_battle.won",
            count = 1,
            where = {
                battle_id = "turn_battle.training_slime",
            },
        },
    },
    on_complete = {
        {type = "give_item", item = "item.potion"},
        {type = "add_currency", amount = 25, reason = "quest.first_steps"},
    },
}

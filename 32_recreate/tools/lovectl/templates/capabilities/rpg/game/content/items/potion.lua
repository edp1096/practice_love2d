return {
    schema_version = 1,
    kind = "item",
    id = "item.potion",
    name_key = "item.potion.name",
    description_key = "item.potion.description",
    stack_limit = 10,
    consumable = true,
    effects = {
        {type = "heal", amount = 25},
    },
    value = 20,
}

return {
    schema_version = 1,
    kind = "actor",
    id = "actor.field_potion",
    name = "Field Potion",
    tags = {"world_item", "pickup"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 12,
            solid = false,
        },
        ["render.sprite"] = {
            sprite = "sprite.poison_jar",
        },
        ["motion.facing"] = {},
        ["rpg.interactable"] = {
            input = "interact",
            range = 56,
            pages = {
                {
                    id = "available",
                    prompt_key = "interaction.collect",
                    actions = {
                        {
                            type = "give_item",
                            item = "item.potion",
                            amount = 1,
                        },
                        {
                            type = "set_flag",
                            name = "world.field_potion_collected",
                        },
                        {
                            type = "show_notice",
                            text_key = "notice.field_potion.collected",
                            tone = "success",
                            duration = 3,
                        },
                    },
                },
                {
                    id = "collected",
                    condition = {
                        type = "flag",
                        name = "world.field_potion_collected",
                    },
                    prompt_key = "interaction.inspect",
                    actions = {
                        {
                            type = "show_notice",
                            text_key = "notice.field_potion.empty",
                            duration = 2,
                        },
                    },
                },
            },
        },
    },
}

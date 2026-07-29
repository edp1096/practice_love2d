return {
    schema_version = 1,
    kind = "actor",
    id = "actor.merchant",
    name = "Merchant",
    tags = {"merchant"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 17,
            solid = false,
        },
        ["render.shape"] = {
            shape = "circle",
            radius = 17,
            color = {0.95, 0.62, 0.2, 1},
            outline = {1, 0.9, 0.55, 1},
            label = "SHOP",
        },
        ["rpg.interactable"] = {
            input = "interact",
            range = 72,
            prompt_key = "interaction.shop",
            actions = {
                {type = "open_shop", shop = "shop.general"},
            },
        },
    },
}

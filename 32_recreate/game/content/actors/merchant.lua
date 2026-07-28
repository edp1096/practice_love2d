return {
    schema_version = 1,
    kind = "actor",
    id = "actor.merchant",
    name = "Merchant",
    tags = {"npc", "merchant"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 18,
            solid = false,
        },
        ["render.shape"] = {
            shape = "circle",
            radius = 18,
            color = {0.95, 0.62, 0.2, 1.0},
            outline = {1.0, 0.9, 0.58, 1.0},
            label = "SHOP",
        },
        ["rpg.interactable"] = {
            input = "interact",
            range = 70,
            prompt_key = "interaction.shop",
            actions = {
                {
                    type = "open_shop",
                    shop = "shop.village",
                },
            },
        },
    },
}

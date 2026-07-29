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
        ["render.sprite"] = {
            sprite = "sprite.merchant",
        },
        ["motion.facing"] = {},
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

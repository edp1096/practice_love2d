return {
    schema_version = 1,
    kind = "actor",
    id = "actor.guide",
    name = "Guild Guide",
    tags = {"npc"},
    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 18,
            solid = false,
        },
        ["render.sprite"] = {
            sprite = "sprite.guide",
        },
        ["motion.facing"] = {},
        ["rpg.interactable"] = {
            input = "interact",
            range = 70,
            prompt_key = "interaction.talk",
            actions = {
                {
                    type = "start_dialogue",
                    dialogue = "dialogue.guide",
                },
            },
        },
    },
}

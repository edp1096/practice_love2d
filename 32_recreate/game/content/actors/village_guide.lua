return {
    schema_version = 1,
    kind = "actor",
    id = "actor.village_guide",
    name = "Village Guide",
    tags = {"npc", "guide"},
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
                    dialogue = "dialogue.village_guide",
                },
            },
        },
    },
}

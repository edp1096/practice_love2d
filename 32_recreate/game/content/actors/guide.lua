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
        ["render.shape"] = {
            shape = "circle",
            radius = 18,
            color = {0.28, 0.68, 1.0, 1.0},
            outline = {0.75, 0.92, 1.0, 1.0},
            label = "GUIDE",
        },
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

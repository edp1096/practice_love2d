return {
    schema_version = 1,
    kind = "dialogue",
    id = "dialogue.guide",
    name_key = "dialogue.guide.name",
    start = "start",
    nodes = {
        start = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.start",
            choices = {
                {
                    id = "continue",
                    text_key = "dialogue.guide.continue",
                    next = "finish",
                },
                {
                    id = "leave",
                    text_key = "dialogue.guide.leave",
                },
            },
        },
        finish = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.finish",
        },
    },
}

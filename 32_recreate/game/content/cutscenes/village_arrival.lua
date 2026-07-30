return {
    schema_version = 1,
    kind = "cutscene",
    id = "cutscene.village_arrival",
    name = "Village Arrival",
    skippable = true,
    steps = {
        {
            id = "threat",
            text_key = "cutscene.village_arrival.threat",
        },
        {
            id = "call",
            speaker_key = "npc.village_guide.name",
            text_key = "cutscene.village_arrival.call",
        },
    },
    on_complete = {
        {
            type = "set_flag",
            name = "story.village_arrival_seen",
        },
        {
            type = "show_notice",
            text_key = "notice.intro",
            duration = 4,
        },
    },
}

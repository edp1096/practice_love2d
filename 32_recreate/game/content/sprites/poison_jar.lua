return {
    schema_version = 1,
    kind = "sprite",
    id = "sprite.poison_jar",
    name = "Poison Jar World Item",
    asset = "image.poison_jar_sheet",
    frame_width = 32,
    frame_height = 32,
    scale = 1,
    origin_x = 16,
    origin_y = 16,
    default_clip = "idle",
    clips = {
        idle = {
            frames = {
                {1, 1}, {2, 1}, {3, 1}, {4, 1}, {5, 1},
                {6, 1}, {7, 1}, {8, 1}, {9, 1},
            },
            fps = 8,
        },
    },
    state_map = {
        idle_up = "idle",
        idle_down = "idle",
        idle_left = "idle",
        idle_right = "idle",
    },
}

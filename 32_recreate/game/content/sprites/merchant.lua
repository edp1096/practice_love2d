return {
    schema_version = 1,
    kind = "sprite",
    id = "sprite.merchant",
    name = "Merchant Animation",
    asset = "image.merchant_sheet",
    frame_width = 48,
    frame_height = 48,
    scale = 2,
    origin_x = 24,
    origin_y = 24,
    default_clip = "idle_down",
    clips = {
        idle_down = {
            frames = {{1, 1}, {2, 1}, {3, 1}, {4, 1}},
            fps = 5,
        },
        idle_up = {
            frames = {{5, 1}, {6, 1}, {7, 1}, {8, 1}},
            fps = 5,
        },
        idle_left = {
            frames = {{1, 2}, {2, 2}, {3, 2}, {4, 2}},
            fps = 5,
        },
        idle_right = {
            frames = {{5, 2}, {6, 2}, {7, 2}, {8, 2}},
            fps = 5,
        },
    },
    state_map = {
        idle_up = "idle_up",
        idle_down = "idle_down",
        idle_left = "idle_left",
        idle_right = "idle_right",
    },
}

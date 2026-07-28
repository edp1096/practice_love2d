return {
    schema_version = 1,
    kind = "sprite",
    id = "sprite.slime",
    name = "Red Slime Animation",
    asset = "image.slime_red_sheet",

    frame_width = 16,
    frame_height = 32,
    scale = 2.5,
    origin_x = 8,
    origin_y = 24,
    default_clip = "idle_right",

    clips = {
        idle_right = {
            frames = {{1, 1}, {2, 1}, {3, 1}},
            fps = 5,
        },
        move_right = {
            frames = {{4, 1}, {5, 1}, {6, 1}, {7, 1}},
            fps = 8,
        },
        attack_right = {
            frames = {{8, 1}, {9, 1}, {10, 1}, {11, 1}},
            fps = 10,
            loop = false,
        },
        idle_left = {
            frames = {{1, 2}, {2, 2}, {3, 2}},
            fps = 5,
        },
        move_left = {
            frames = {{4, 2}, {5, 2}, {6, 2}, {7, 2}},
            fps = 8,
        },
        attack_left = {
            frames = {{8, 2}, {9, 2}, {10, 2}, {11, 2}},
            fps = 10,
            loop = false,
        },
    },

    state_map = {
        idle_up = "idle_right",
        idle_down = "idle_right",
        idle_left = "idle_left",
        idle_right = "idle_right",
        move_up = "move_right",
        move_down = "move_right",
        move_left = "move_left",
        move_right = "move_right",
        attack_up = "attack_right",
        attack_down = "attack_right",
        attack_left = "attack_left",
        attack_right = "attack_right",
    },
}

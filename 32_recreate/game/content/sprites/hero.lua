return {
    schema_version = 1,
    kind = "sprite",
    id = "sprite.hero",
    name = "Hero Animation",
    asset = "image.player_sheet",

    frame_width = 48,
    frame_height = 48,
    scale = 2,
    origin_x = 24,
    origin_y = 24,
    default_clip = "idle_down",

    clips = {
        idle_down = {
            frames = {{1, 1}, {2, 1}, {3, 1}, {4, 1}},
            fps = 7,
        },
        idle_up = {
            frames = {{5, 1}, {6, 1}, {7, 1}, {8, 1}},
            fps = 7,
        },
        idle_left = {
            frames = {{1, 2}, {2, 2}, {3, 2}, {4, 2}},
            fps = 7,
        },
        idle_right = {
            frames = {{5, 2}, {6, 2}, {7, 2}, {8, 2}},
            fps = 7,
        },

        run_down = {
            frames = {
                {1, 6}, {2, 6}, {3, 6},
                {4, 6}, {5, 6}, {6, 6},
            },
            fps = 12,
        },
        run_up = {
            frames = {
                {7, 6}, {8, 6}, {1, 7},
                {2, 7}, {3, 7}, {4, 7},
            },
            fps = 12,
        },
        run_left = {
            frames = {
                {5, 7}, {6, 7}, {7, 7},
                {8, 7}, {1, 8}, {2, 8},
            },
            fps = 12,
        },
        run_right = {
            frames = {
                {3, 8}, {4, 8}, {5, 8},
                {6, 8}, {7, 8}, {8, 8},
            },
            fps = 12,
        },

        attack_down = {
            frames = {{1, 11}, {2, 11}, {3, 11}, {4, 11}},
            fps = 13,
            loop = false,
        },
        attack_up = {
            frames = {{5, 11}, {6, 11}, {7, 11}, {8, 11}},
            fps = 13,
            loop = false,
        },
        attack_left = {
            frames = {{1, 12}, {2, 12}, {3, 12}, {4, 12}},
            fps = 13,
            loop = false,
        },
        attack_right = {
            frames = {{5, 12}, {6, 12}, {7, 12}, {8, 12}},
            fps = 13,
            loop = false,
        },
    },

    state_map = {
        idle_up = "idle_up",
        idle_down = "idle_down",
        idle_left = "idle_left",
        idle_right = "idle_right",
        move_up = "run_up",
        move_down = "run_down",
        move_left = "run_left",
        move_right = "run_right",
        attack_up = "attack_up",
        attack_down = "attack_down",
        attack_left = "attack_left",
        attack_right = "attack_right",
    },
}

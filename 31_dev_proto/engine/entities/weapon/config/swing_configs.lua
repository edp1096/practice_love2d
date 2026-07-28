-- entities/weapon/config/swing_configs.lua
-- Swing direction configurations

-- Degrees
-- math.pi = 180
-- math.pi / 2 = 90
-- math.pi / 3 = 60
-- math.pi / 4 = 45


local swing_configs = {}

swing_configs.SWING_CONFIGS = {
    right = {
        type = "vertical",
        start_angle = -math.pi / 2,
        end_angle = math.pi / 2,
        flip_x = true
    },
    left = {
        type = "vertical",
        start_angle = -math.pi / 2,
        end_angle = math.pi / 2,
        flip_x = false
    },
    down = {
        type = "horizontal",
        start_angle = math.pi,
        end_angle = 0,
        flip_x = false
    },
    up = {
        type = "horizontal",
        start_angle = 0,
        end_angle = math.pi,
        flip_x = false
    }
}

return swing_configs

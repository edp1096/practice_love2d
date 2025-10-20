-- entities/weapon/config/swing_configs.lua
-- Swing direction configurations

local swing_configs = {}

swing_configs.SWING_CONFIGS = {
    right = {
        type = "vertical",
        start_angle = -math.pi / 2,
        end_angle = math.pi / 2,
        flip_x = false
    },
    left = {
        type = "vertical",
        start_angle = -math.pi / 2,
        end_angle = math.pi / 2,
        flip_x = true
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

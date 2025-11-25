-- entities/weapon/config/hand_anchors.lua
-- Hand anchor positions for each animation frame

local hand_anchors = {}

hand_anchors.HAND_ANCHORS = {
    -- Idle animations (4 frames each)
    idle_right = {
        { x = -1, y = 7, angle = -math.pi / 12 },
        { x = -2, y = 8, angle = -math.pi / 12 + 0.05 },
        { x = -2, y = 9, angle = -math.pi / 12 },
        { x = -1, y = 9, angle = -math.pi / 12 - 0.05 }
    },
    idle_left = {
        { x = 0, y = 7, angle = -math.pi },
        { x = 0, y = 6, angle = -math.pi + 0.05 },
        { x = 0, y = 7, angle = -math.pi },
        { x = 0, y = 8, angle = -math.pi - 0.05 },
    },
    idle_down = {
        { x = -6, y = 6, angle = math.pi / 2 },
        { x = -6, y = 6, angle = 1.6208 },
        { x = -5, y = 6, angle = math.pi / 2 },
        { x = -6, y = 8, angle = 1.5208 },
    },
    idle_up = {
        { x = 4, y = 7, angle = -math.pi / 2 },
        { x = 4, y = 6, angle = -1.5208 },
        { x = 4, y = 7, angle = -math.pi / 2 },
        { x = 3, y = 8, angle = -1.6208 },
    },

    -- Walk animations
    walk_right = {
        { x = 6,  y = 5, angle = -math.pi / 12 },
        { x = 3,  y = 7, angle = -math.pi / 12 },
        { x = -6, y = 7, angle = -math.pi / 12 },
        { x = -8, y = 7, angle = -math.pi / 12 },
        { x = -4, y = 7, angle = -math.pi / 12 },
        { x = 3,  y = 7, angle = -math.pi / 12 },
    },
    walk_left = {
        { x = 7,  y = 6, angle = math.pi },
        { x = 4,  y = 6, angle = math.pi },
        { x = -5, y = 6, angle = math.pi },
        { x = -8, y = 5, angle = math.pi },
        { x = -4, y = 7, angle = math.pi },
        { x = 5,  y = 6, angle = math.pi },
    },
    walk_down = {
        { x = -5, y = 4, angle = math.pi / 2 },
        { x = -5, y = 5, angle = 1.7708 },
        { x = -6, y = 7, angle = 1.3708 },
        { x = -4, y = 8, angle = math.pi / 2 },
    },
    walk_up = {
        { x = 3, y = 6,  angle = -math.pi / 2 },
        { x = 1, y = 10, angle = -1.3708 },
        { x = 4, y = 6,  angle = -1.7708 },
        { x = 5, y = 6,  angle = -math.pi / 2 },
    },

    -- Run animations (6 frames each)
    run_right = {
        { x = 6,  y = 5, angle = -math.pi / 12 },
        { x = 4,  y = 6, angle = -math.pi / 12 },
        { x = -4, y = 7, angle = -math.pi / 12 },
        { x = -8, y = 6, angle = -math.pi / 12 },
        { x = -4, y = 7, angle = -math.pi / 12 },
        { x = 4,  y = 6, angle = -math.pi / 12 },
    },
    run_left = {
        { x = 7,  y = 5, angle = math.pi },
        { x = 4,  y = 6, angle = math.pi },
        { x = -4, y = 7, angle = math.pi },
        { x = -8, y = 6, angle = math.pi },
        { x = -4, y = 7, angle = math.pi },
        { x = 5,  y = 6, angle = math.pi },
    },
    run_down = {
        { x = -5, y = 4, angle = math.pi / 2 },
        { x = -5, y = 5, angle = 1.7708 },
        { x = -6, y = 7, angle = 1.3708 },
        { x = -5, y = 8, angle = math.pi / 2 },
        { x = -6, y = 7, angle = 1.7708 },
        { x = -5, y = 5, angle = 1.3708 },
    },
    run_up = {
        { x = 3, y = 5,  angle = -math.pi / 2 },
        { x = 2, y = 6,  angle = -1.3708 },
        { x = 4, y = 8,  angle = -1.7708 },
        { x = 5, y = 7,  angle = -math.pi / 2 },
        { x = 4, y = 8,  angle = -1.3708 },
        { x = 2, y = 6,  angle = -1.7708 },
    },

    -- Attack animations (4 frames each)
    attack_right = {
        { x = 6,  y = -2, angle = -math.pi / 2 },
        { x = 5,  y = -7, angle = -math.pi },
        { x = 5,  y = 8,  angle = math.pi / 2 },
        { x = -2, y = 7,  angle = math.pi / 3 }
    },
    attack_left = {
        { x = -7, y = -2, angle = -math.pi / 2 },
        { x = -5, y = -8, angle = math.pi / 6 },
        { x = -6, y = 8,  angle = math.pi / 2 },
        { x = 2,  y = 8,  angle = math.pi * 2 / 3 },
    },
    attack_down = {
        { x = -6, y = -7,  angle = math.pi * 3 / 2 },
        { x = -7, y = -12, angle = math.pi * 3 / 2 },
        { x = 2,  y = 10,  angle = math.pi / 2 },
        { x = 2,  y = 6,   angle = math.pi / 6 },
    },
    attack_up = {
        { x = 4,  y = -7,  angle = 0 },
        { x = 6,  y = -13, angle = math.pi / 2 },
        { x = -8, y = 6,   angle = math.pi },
        { x = -4, y = 8,   angle = math.pi * 5 / 6 }
    }
}

return hand_anchors

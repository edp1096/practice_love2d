-- data/input_config.lua
-- Centralized input mapping configuration for easy customization

return {
    -- Movement controls (analog or digital)
    movement = {
        move_left = {
            keyboard = { "a", "left" },
            gamepad_axis = { axis = "leftx", negative = true }
        },
        move_right = {
            keyboard = { "d", "right" },
            gamepad_axis = { axis = "leftx", negative = false }
        },
        move_up = {
            keyboard = { "w", "up" },
            gamepad_axis = { axis = "lefty", negative = true }
        },
        move_down = {
            keyboard = { "s", "down" },
            gamepad_axis = { axis = "lefty", negative = false }
        }
    },

    -- Aiming controls (right stick or mouse)
    aim = {
        aim = {
            gamepad_axis = { axis = "rightx", axis2 = "righty" }
        }
    },

    -- Combat actions
    combat = {
        attack = {
            mouse = 1,
            gamepad = "a" -- Cross button (DualSense)
        },
        parry = {
            mouse = 2,
            gamepad = "x" -- Square button (DualSense)
        },
        dodge = {
            keyboard = { "space" },
            gamepad = "b" -- Circle button (DualSense)
        },
        interact = {
            keyboard = { "f" },
            gamepad = "y" -- Triangle button (DualSense)
        }
    },

    -- Menu navigation
    menu = {
        menu_up = {
            keyboard = { "w", "up" },
            gamepad_dpad = "up"
        },
        menu_down = {
            keyboard = { "s", "down" },
            gamepad_dpad = "down"
        },
        menu_left = {
            keyboard = { "a", "left" },
            gamepad_dpad = "left"
        },
        menu_right = {
            keyboard = { "d", "right" },
            gamepad_dpad = "right"
        },
        menu_select = {
            keyboard = { "return", "space" },
            mouse = 1,
            gamepad = "a"
        },
        menu_back = {
            keyboard = { "escape" },
            gamepad = "b"
        }
    },

    -- System controls
    system = {
        pause = {
            keyboard = { "p", "escape" },
            gamepad = "start"
        },
        quicksave_1 = {
            keyboard = { "f1" },
            gamepad = "leftshoulder" -- L1
        },
        quicksave_2 = {
            keyboard = { "f2" },
            gamepad = "rightshoulder" -- R1
        },
        quicksave_3 = {
            keyboard = { "f3" }
        }
    },

    -- Default gamepad settings
    gamepad_settings = {
        deadzone = 0.15,
        vibration_enabled = true,
        vibration_strength = 1.0
    },

    -- Button prompts (DualSense controller)
    button_prompts = {
        -- Face buttons
        a = "[✕]", -- Cross
        b = "[○]", -- Circle
        x = "[□]", -- Square
        y = "[△]", -- Triangle

        -- Shoulder buttons
        leftshoulder = "[L1]",
        rightshoulder = "[R1]",

        -- System buttons
        start = "[Options]",
        back = "[Share]",

        -- Mouse
        mouse_1 = "[LMB]",
        mouse_2 = "[RMB]"
    }
}

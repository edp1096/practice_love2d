-- data/input_config.lua
-- Centralized input mapping configuration for easy customization

return {
    -- Movement controls (analog or digital)
    movement = {
        move_left = {
            keyboard = { "a", "left" },
            gamepad_axis = { axis = "leftx", negative = true },
            gamepad_dpad = "left"
        },
        move_right = {
            keyboard = { "d", "right" },
            gamepad_axis = { axis = "leftx", negative = false },
            gamepad_dpad = "right"
        },
        move_up = {
            keyboard = { "w", "up" },
            gamepad_axis = { axis = "lefty", negative = true },
            gamepad_dpad = "up"
        },
        move_down = {
            keyboard = { "s", "down" },
            gamepad_axis = { axis = "lefty", negative = false },
            gamepad_dpad = "down"
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
        },
        use_item = {
            keyboard = { "q" },
            gamepad = "leftshoulder" -- L1 button (DualSense)
        },
        next_item = {
            keyboard = { "tab" },
            gamepad = "rightshoulder" -- R1 button (DualSense)
        }
    },

    -- Inventory controls
    inventory = {
        open_inventory = {
            keyboard = { "i" }
        },
        slot_1 = {
            keyboard = { "1" }
        },
        slot_2 = {
            keyboard = { "2" }
        },
        slot_3 = {
            keyboard = { "3" }
        },
        slot_4 = {
            keyboard = { "4" }
        },
        slot_5 = {
            keyboard = { "5" }
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
        manual_save = {
            keyboard = { "f9" }
        }
    },

    -- Default gamepad settings
    gamepad_settings = {
        deadzone = 0.15,
        vibration_enabled = true,
        vibration_strength = 1.0,
        mobile_vibration_enabled = true -- Separate control for mobile device vibration
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

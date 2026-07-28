return {
    id = "recreate.maker_runtime",
    title = "Recreate 2D Maker Runtime",
    initial_stage = "stage.action_room",

    fixed_dt = 1 / 60,
    maximum_steps = 8,

    content_roots = {
        "game/content",
    },

    features = {
        "engine.features.movement.topdown",
        "engine.features.movement.platformer",
        "engine.features.geometry",
        "engine.features.navigation",
        "engine.features.camera",
        "engine.features.tilemap",
        "engine.features.action.chase_ai",
        "engine.features.action.hitstop",
        "engine.features.action.knockback",
        "engine.features.action.projectile",
        "engine.features.action.status",
        "engine.features.action.encounter",
        "engine.features.action.dodge",
        "engine.features.action.parry",
        "engine.features.rpg.flags",
        "engine.features.rpg.inventory",
        "engine.features.rpg.equipment",
        "engine.features.rpg.locale",
        "engine.features.rpg.quest",
        "engine.features.rpg.dialogue",
        "engine.features.rpg.shop",
        "engine.features.rpg.interaction",
        "engine.features.rpg.hud",
        "engine.features.presentation.font",
        "engine.features.presentation.basic",
        "engine.features.presentation.sprite",
    },

    locale = {
        default = "locale.ko",
        fallback = "locale.en",
    },
    font = {
        asset = "font.ui",
        size = 16,
    },

    input = {
        actions = {
            move_up = {
                keys = {"w", "up"},
                buttons = {"dpup"},
            },
            move_down = {
                keys = {"s", "down"},
                buttons = {"dpdown"},
            },
            move_left = {
                keys = {"a", "left"},
                buttons = {"dpleft"},
            },
            move_right = {
                keys = {"d", "right"},
                buttons = {"dpright"},
            },
            attack = {
                keys = {"space", "z"},
                buttons = {"x"},
            },
            special = {
                keys = {"f", "v"},
                buttons = {"y"},
            },
            technique = {
                keys = {"q"},
                buttons = {"rightshoulder"},
            },
            jump = {
                keys = {"w", "up"},
                buttons = {"a"},
            },
            parry = {
                keys = {"c", "lctrl", "rctrl"},
                buttons = {"leftshoulder"},
            },
            dodge = {
                keys = {"lshift", "rshift", "x"},
                buttons = {"b"},
            },
            interact = {
                keys = {"e"},
                buttons = {"x"},
            },
            menu_up = {
                keys = {"w", "up"},
                buttons = {"dpup"},
            },
            menu_down = {
                keys = {"s", "down"},
                buttons = {"dpdown"},
            },
            menu_left = {
                keys = {"a", "left"},
                buttons = {"dpleft"},
            },
            menu_right = {
                keys = {"d", "right"},
                buttons = {"dpright"},
            },
            menu_confirm = {
                keys = {"return", "space"},
                buttons = {"a"},
            },
            menu_cancel = {
                keys = {"escape", "backspace"},
                buttons = {"b"},
            },
            restart = {
                keys = {"r"},
                buttons = {"back"},
            },
            debug_overlay = {
                keys = {"f1"},
                buttons = {},
            },
        },
    },
}

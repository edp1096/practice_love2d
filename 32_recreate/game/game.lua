return {
    id = "recreate.maker_runtime",
    profile = "action-rpg",
    title = "고요한 숲의 수호자",
    initial_stage = "stage.village",

    fixed_dt = 1 / 60,
    maximum_steps = 8,
    maximum_action_depth = 64,

    content_roots = {
        "game/content",
    },

    features = {
        "engine.features.game_flow",
        "engine.features.movement.topdown",
        "engine.features.movement.platformer",
        "engine.features.geometry",
        "engine.features.navigation",
        "engine.features.camera",
        "engine.features.presentation.impact",
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
    audio = {
        master_volume = 0.8,
        music_volume = 0.45,
        sfx_volume = 0.8,
        cues = {
            {
                event = "actor.killed",
                asset = "audio.kill",
                volume = 0.9,
            },
            {
                event = "attack.parried",
                asset = "audio.parry",
                volume = 1,
            },
            {
                event = "attack.started",
                asset = "audio.attack",
                volume = 0.75,
            },
            {
                event = "damage.applied",
                asset = "audio.hit",
                volume = 0.85,
            },
            {
                event = "platformer.jumped",
                asset = "audio.jump",
                volume = 0.7,
            },
            {
                event = "projectile.spawned",
                asset = "audio.projectile",
                volume = 0.75,
            },
            {
                event = "quest.completed",
                asset = "audio.quest",
                volume = 1,
            },
            {
                event = "ui.cancel",
                asset = "audio.ui_cancel",
                volume = 0.7,
            },
            {
                event = "ui.confirm",
                asset = "audio.ui_confirm",
                volume = 0.7,
            },
        },
        stage_music = {
            {
                stage = "stage.action_room",
                asset = "audio.forest_theme",
                volume = 0.75,
            },
            {
                stage = "stage.encounter_room",
                asset = "audio.forest_theme",
                volume = 0.8,
            },
            {
                stage = "stage.platformer_room",
                asset = "audio.forest_theme",
                volume = 0.7,
            },
            {
                stage = "stage.rpg_village",
                asset = "audio.forest_theme",
                volume = 0.65,
            },
            {
                stage = "stage.village",
                asset = "audio.forest_theme",
                volume = 0.65,
            },
            {
                stage = "stage.world_grove",
                asset = "audio.forest_theme",
                volume = 0.8,
            },
            {
                stage = "stage.world_hub",
                asset = "audio.forest_theme",
                volume = 0.7,
            },
        },
    },
    flow = {
        save_slot = "campaign",
        start_stage = "stage.village",
        start_spawn = "default",
        title = {
            heading_key = "flow.title.heading",
            message_key = "flow.title.message",
        },
        game_over = {
            heading_key = "flow.game_over.heading",
            message_key = "flow.game_over.message",
        },
        ending = {
            heading_key = "flow.ending.heading",
            message_key = "flow.ending.message",
        },
    },
    impact_feedback = {
        damage = {
            duration = 0.09,
            magnitude = 2.5,
        },
        kill = {
            duration = 0.16,
            magnitude = 5,
        },
        parry = {
            duration = 0.14,
            magnitude = 6,
        },
        perfect_parry = {
            duration = 0.2,
            magnitude = 10,
        },
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
            pause = {
                keys = {"escape", "p"},
                buttons = {"start"},
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

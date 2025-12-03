-- game/data/cutscenes.lua
-- Configuration for cutscenes (intros, level transitions, endings)
--
-- Structure:
--   cutscene_id = {
--     background = "path/to/image.png",
--     bgm = "bgm_name",              -- BGM name from sounds.lua
--     messages_key = {               -- Translation keys (preferred)
--       "cutscene.level1.message_1",
--       "cutscene.level1.message_2",
--     },
--     messages = { "Fallback 1" },   -- Direct text (fallback)
--     speaker = ""                   -- Empty for narrator
--   }

return {
    level1 = {
        background = "assets/maps/level1/scene_intro.png",
        bgm = "intro_level1",  -- BGM name from sounds.lua
        messages_key = {
            "cutscene.level1.message_1",
            "cutscene.level1.message_2",
            "cutscene.level1.message_3"
        },
        -- Optional: speaker name (empty string for narrator)
        speaker = ""
    },

    level2 = {
        background = "assets/maps/level2/scene_intro.jpg",
        bgm = "intro_level2",  -- BGM name from sounds.lua
        messages_key = {
            "cutscene.level2.message_1",
            "cutscene.level2.message_2",
            "cutscene.level2.message_3"
        },
        speaker = ""
    },

    level3 = {
        background = "assets/maps/level3/scene_intro.jpg",
        messages_key = {
            "cutscene.level3.message_1",
            "cutscene.level3.message_2"
        },
        speaker = ""
    },

    -- Ending scene
    ending = {
        background = "assets/maps/ending.jpg",
        bgm = "victory",  -- Short victory music for cutscene
        messages_key = {
            "cutscene.ending.message_1",
            "cutscene.ending.message_2",
            "cutscene.ending.message_3"
        },
        speaker = "",
        -- Special flag to indicate this is an ending (goes to gameclear screen)
        is_ending = true
    },

    -- Example for future ending scenes
    ending_good = {
        background = "assets/scenes/ending_good.jpg",
        bgm = "ending",
        messages_key = {
            "cutscene.ending_good.message_1",
            "cutscene.ending_good.message_2",
            "cutscene.ending_good.message_3"
        },
        speaker = "",
        is_ending = true
    },

    ending_bad = {
        background = "assets/scenes/ending_bad.jpg",
        bgm = "gameover",
        messages_key = {
            "cutscene.ending_bad.message_1",
            "cutscene.ending_bad.message_2",
            "cutscene.ending_bad.message_3"
        },
        speaker = "",
        is_ending = true
    }
}

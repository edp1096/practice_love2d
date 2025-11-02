-- data/intro_configs.lua
-- Configuration for intro/cutscene for different levels and endings

return {
    level1 = {
        background = "assets/maps/level1/scene_intro.png",
        bgm = "intro_level1",  -- BGM name from sounds.lua
        messages = {
            "Welcome to the adventure!",
            "Your journey begins now...",
            "Good luck, brave hero!"
        },
        -- Optional: speaker name (empty string for narrator)
        speaker = ""
    },

    level2 = {
        background = "assets/maps/level2/scene_intro.jpg",
        bgm = "intro_level2",  -- BGM name from sounds.lua
        messages = {
            "Good bye level 1!",
            "Hello level 2!",
            "Prepare for new challenges..."
        },
        speaker = ""
    },

    level3 = {
        background = "assets/maps/level3/scene_intro.jpg",
        messages = {
            "The final challenge awaits...",
            "Are you ready?"
        },
        speaker = ""
    },

    -- Ending scene
    ending = {
        background = "assets/maps/ending.jpg",
        bgm = "ending",
        messages = {
            "Congratulations!",
            "You have completed your journey!",
            "Thank you for playing."
        },
        speaker = "",
        -- Special flag to indicate this is an ending (goes to gameclear screen)
        is_ending = true
    },

    -- Example for future ending scenes
    ending_good = {
        background = "assets/scenes/ending_good.jpg",
        bgm = "ending",
        messages = {
            "Congratulations!",
            "You have saved the world!",
            "Thank you for playing."
        },
        speaker = "",
        is_ending = true
    },

    ending_bad = {
        background = "assets/scenes/ending_bad.jpg",
        bgm = "gameover",
        messages = {
            "The darkness prevails...",
            "But hope remains.",
            "Try again?"
        },
        speaker = "",
        is_ending = true
    }
}

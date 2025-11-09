-- game/data/scenes.lua
-- Data-driven scene configurations

local scenes = {}

-- Main Menu
scenes.menu = {
  type = "menu",
  title = "Hello Love2D",
  bgm = "menu",

  -- Dynamic options based on save files
  options_logic = "has_saves",  -- Special: check save files
  options_with_saves = { "Continue", "New Game", "Load Game", "Settings", "Quit" },
  options_no_saves = { "New Game", "Settings", "Quit" },

  -- Actions (declarative)
  actions = {
    ["Continue"] = { action = "load_recent_save" },
    ["New Game"] = { action = "start_new_game" },  -- Start new game with intro
    ["Load Game"] = { action = "switch_scene", scene = "load" },
    ["Settings"] = { action = "switch_scene", scene = "settings" },
    ["Quit"] = { action = "quit" }
  },

  back_action = { action = "quit" }
}

-- Pause Menu
scenes.pause = {
  type = "menu",
  title = "PAUSED",
  overlay = true,
  overlay_alpha = 0.7,

  options = { "Resume", "Restart from Here", "Load Last Save", "Settings", "Quit to Menu" },

  actions = {
    ["Resume"] = { action = "pop_scene", sfx = "ui/unpause", resume_bgm = true },
    ["Restart from Here"] = { action = "restart_current" },
    ["Load Last Save"] = { action = "restart_from_save" },
    ["Settings"] = { action = "push_scene", scene = "settings" },
    ["Quit to Menu"] = { action = "switch_scene", scene = "menu" }
  },

  back_action = { action = "pop_scene", sfx = "ui/unpause", resume_bgm = true }
}

-- GameOver Menu (on death)
scenes.gameover = {
  type = "menu",
  title = "GAME OVER",
  bgm = "gameover",
  overlay = true,
  overlay_alpha = 0.8,

  -- Flash effect
  flash = {
    enabled = true,
    color = { 0.8, 0, 0 },  -- Red flash
    initial_alpha = 1.0,
    fade_speed = 2.0
  },

  options = { "Restart from Here", "Load Last Save", "Quit to Menu" },

  actions = {
    ["Restart from Here"] = { action = "restart_current" },
    ["Load Last Save"] = { action = "restart_from_save" },
    ["Quit to Menu"] = { action = "switch_scene", scene = "menu" }
  },

  back_action = { action = "switch_scene", scene = "menu" }
}

-- Ending Menu (on game clear)
scenes.ending = {
  type = "menu",
  title = "CONGRATULATIONS!",
  bgm = "ending",

  -- Flash effect
  flash = {
    enabled = true,
    color = { 1, 0.8, 0 },  -- Gold flash
    initial_alpha = 1.0,
    fade_speed = 1.5
  },

  options = { "New Game", "Continue Playing", "Quit to Menu" },

  actions = {
    ["New Game"] = { action = "switch_scene", scene = "newgame" },
    ["Continue Playing"] = { action = "restart_from_save" },
    ["Quit to Menu"] = { action = "switch_scene", scene = "menu" }
  },

  back_action = { action = "switch_scene", scene = "menu" }
}

-- Settings Menu
scenes.settings = {
  type = "settings",
  title = "Settings",

  -- Options configuration
  options = {
    -- Desktop only
    desktop = {
      { name = "Resolution", type = "list", config_key = "Window.Width,Window.Height",
        values = {"640x360", "854x480", "960x540", "1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"} },
      { name = "Fullscreen", type = "toggle", config_key = "Window.FullScreen" },
      { name = "Monitor", type = "cycle", config_key = "Window.Monitor", requires_multiple_monitors = true },
    },

    -- Common (all platforms)
    common = {
      { name = "Master Volume", type = "percent", config_key = "Sound.MasterVolume", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name = "BGM Volume", type = "percent", config_key = "Sound.BGMVolume", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name = "SFX Volume", type = "percent", config_key = "Sound.SFXVolume", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name = "Mute", type = "toggle", config_key = "Sound.Muted" },
    },

    -- Gamepad (if connected)
    gamepad = {
      { name = "Vibration", type = "toggle", config_key = "Input.VibrationEnabled" },
      { name = "Vibration Strength", type = "percent", config_key = "Input.VibrationStrength", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name = "Deadzone", type = "percent", config_key = "Input.Deadzone", values = {0.05, 0.10, 0.15, 0.20, 0.25, 0.30} },
    },

    -- Mobile only
    mobile = {
      { name = "Mobile Vibration", type = "toggle", config_key = "Input.MobileVibrationEnabled" },
    },
  },

  back_action = { action = "pop_scene" }
}

return scenes

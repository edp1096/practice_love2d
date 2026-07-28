-- game/data/scenes.lua
-- Data-driven scene configurations
-- Uses locale keys for i18n support

local scenes = {}

-- Main Menu
scenes.menu = {
  type = "menu",
  title = "Hello Love2D",  -- Game title (not localized)
  bgm = "menu",

  -- Dynamic options based on save files (use locale keys)
  options_logic = "has_saves",  -- Special: check save files
  options_with_saves = { "menu.continue", "menu.new_game", "menu.load_game", "menu.settings", "menu.quit" },
  options_no_saves = { "menu.new_game", "menu.settings", "menu.quit" },

  -- Actions (use same locale keys)
  actions = {
    ["menu.continue"] = { action = "load_recent_save" },
    ["menu.new_game"] = { action = "start_new_game" },
    ["menu.load_game"] = { action = "switch_scene", scene = "load" },
    ["menu.settings"] = { action = "switch_scene", scene = "settings" },
    ["menu.quit"] = { action = "quit" }
  }

  -- No back_action - ESC disabled on main menu (use Quit option instead)
}

-- Pause Menu
scenes.pause = {
  type = "menu",
  title_key = "pause.title",  -- Use locale key for title
  overlay = true,
  overlay_alpha = 0.7,

  options = { "pause.resume", "pause.restart_here", "pause.load_last_save", "menu.settings", "menu.quit_to_menu" },

  actions = {
    ["pause.resume"] = { action = "pop_scene", sfx = "ui/unpause", resume_bgm = true },
    ["pause.restart_here"] = { action = "restart_current" },
    ["pause.load_last_save"] = { action = "restart_from_save" },
    ["menu.settings"] = { action = "push_scene", scene = "settings" },
    ["menu.quit_to_menu"] = { action = "switch_scene", scene = "menu" }
  },

  back_action = { action = "pop_scene", sfx = "ui/unpause", resume_bgm = true }
}

-- GameOver Menu (on death)
scenes.gameover = {
  type = "menu",
  title_key = "gameover.title",  -- Use locale key for title
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

  options = { "pause.restart_here", "pause.load_last_save", "menu.quit_to_menu" },

  actions = {
    ["pause.restart_here"] = { action = "restart_current" },
    ["pause.load_last_save"] = { action = "restart_from_save" },
    ["menu.quit_to_menu"] = { action = "switch_scene", scene = "menu" }
  },

  back_action = { action = "switch_scene", scene = "menu" }
}

-- Ending Menu (on game clear)
scenes.ending = {
  type = "menu",
  title_key = "ending.title",  -- Use locale key for title
  bgm = "ending",

  -- Flash effect
  flash = {
    enabled = true,
    color = { 1, 0.8, 0 },  -- Gold flash
    initial_alpha = 1.0,
    fade_speed = 1.5
  },

  options = { "menu.new_game", "menu.quit_to_menu" },

  actions = {
    ["menu.new_game"] = { action = "start_new_game" },
    ["menu.quit_to_menu"] = { action = "switch_scene", scene = "menu" }
  },

  back_action = { action = "switch_scene", scene = "menu" }
}

-- Settings Menu
scenes.settings = {
  type = "settings",
  title_key = "settings.title",  -- Use locale key for title

  -- Options configuration (use locale keys for names)
  options = {
    -- Desktop only
    desktop = {
      { name_key = "settings.resolution", type = "list", config_key = "Window.Width,Window.Height",
        values = {"640x360", "854x480", "960x540", "1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"} },
      { name_key = "settings.fullscreen", type = "toggle", config_key = "Window.FullScreen" },
      { name_key = "settings.monitor", type = "cycle", config_key = "Window.Monitor", requires_multiple_monitors = true },
    },

    -- Common (all platforms)
    common = {
      { name_key = "settings.master_volume", type = "percent", config_key = "Sound.MasterVolume", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name_key = "settings.bgm_volume", type = "percent", config_key = "Sound.BGMVolume", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name_key = "settings.sfx_volume", type = "percent", config_key = "Sound.SFXVolume", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name_key = "settings.mute", type = "toggle", config_key = "Sound.Muted" },
      { name_key = "settings.language", type = "language", config_key = "Locale.Language" },
    },

    -- Gamepad (if connected)
    gamepad = {
      { name_key = "settings.vibration", type = "toggle", config_key = "Input.VibrationEnabled" },
      { name_key = "settings.vibration_strength", type = "percent", config_key = "Input.VibrationStrength", values = {0, 0.25, 0.5, 0.75, 1.0} },
      { name_key = "settings.deadzone", type = "percent", config_key = "Input.Deadzone", values = {0.05, 0.10, 0.15, 0.20, 0.25, 0.30} },
    },

    -- Mobile only
    mobile = {
      { name_key = "settings.mobile_vibration", type = "toggle", config_key = "Input.MobileVibrationEnabled" },
    },
  },

  back_action = { action = "pop_scene" }
}

return scenes

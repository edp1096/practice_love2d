-- game/data/player.lua
-- Player configuration (stats, abilities)

local player_config = {}

-- Basic stats
player_config.stats = {
  speed = 260,      -- run speed (default movement)
  walk_speed = 130, -- walk speed (for indoor maps with move_mode="walk")
  jump_power = 600,
}

-- Combat abilities
player_config.combat = {
  -- Health
  max_health = 100,

  -- Attack
  attack_cooldown = 0.5,
  weapon_sheath_delay = 5.0,

  -- Parry
  parry_window = 0.4,
  parry_perfect_window = 0.2,
  parry_cooldown = 1.0,

  -- Dodge
  dodge_duration = 0.3,
  dodge_cooldown = 1.0,
  dodge_distance = 150,
  dodge_invincible_duration = 0.25,

  -- Hit response
  invincible_duration = 1.0,
  hit_shake_intensity = 6,
}

-- Sprite configuration
player_config.sprite = {
  sheet = "assets/images/player/player-sheet.png",
  width = 48, -- Frame size (with padding)
  height = 48,
  scale = 2,

  -- Actual character size (excluding 8px padding on all sides)
  -- Frame 48x48, padding 8px → character is 16x32
  character_width = 16,
  character_height = 32,
}

-- Collider will be auto-calculated as character_size * scale

-- Animation frames (optional - engine has defaults)
-- Uncomment and modify to use custom sprite sheet layout

player_config.animations = {
  default_move = "run", -- "walk" or "run"
  frames = {
    idle_up         = { "5-8", 1 },
    idle_down       = { "1-4", 1 },
    idle_left       = { "1-4", 2 },
    idle_right      = { "5-8", 2 },

    walk_up         = { "1-4", 4 },
    walk_down       = { "1-4", 3 },
    walk_left       = { { "5-8", 4 }, { "1-2", 5 } },
    walk_right      = { "3-8", 5 },

    run_up          = { { "7-8", 6 }, { "1-4", 7 } },
    run_down        = { "1-6", 6 },
    run_left        = { { "5-8", 7 }, { "1-2", 8 } },
    run_right       = { "3-8", 8 },

    jump_up         = { { "7-8", 6 }, { "1-4", 7 } },
    jump_down       = { "1-6", 6 },
    jump_left       = { {"5-8", 7}, { "1-2", 8 } },
    jump_right      = { "3-8", 8 },

    jump_move_up         = { { "7-8", 6 }, { "1-4", 7 } },
    jump_move_down       = { "1-6", 6 },
    jump_move_left       = { {"5-8", 7}, { "1-2", 8 } },
    jump_move_right      = { "3-8", 8 },

    attack_down     = { "1-4", 11 },
    attack_up       = { "5-8", 11 },
    attack_left     = { "1-4", 12 },
    attack_right    = { "5-8", 12 },

    -- Riding poses (static or animated)
    -- TODO: Update frame indices when ride sprite is added to sheet
    -- Idle pose (standing still on vehicle)
    ride_idle_up    = { "5-8", 1 },  -- placeholder: uses idle_up frame 1
    ride_idle_down  = { "1-4", 1 },  -- placeholder: uses idle_down frame 1
    ride_idle_left  = { "1-4", 2 },  -- placeholder: uses idle_left frame 1
    ride_idle_right = { "5-8", 2 },  -- placeholder: uses idle_right frame 1
    -- Move pose (moving on vehicle)
    ride_move_up    = { "5-6", 9 },  -- placeholder: uses idle_up frames
    ride_move_down  = { "1-2", 9 },  -- placeholder: uses idle_down frames
    ride_move_left  = { "1-2", 10 },  -- placeholder: uses idle_left frames
    ride_move_right = { "5-6", 10 },  -- placeholder: uses idle_right frames
  },
  durations = {
    idle = 0.15,
    walk = 0.1,
    run = 0.08,
    jump = 0.15,
    jump_move = 0.12,
    attack = 0.08,
    ride_idle = 0.15,  -- static pose
    ride_move = 0.3,   -- moving on vehicle
  },
}

-- Starting position (overridden by map spawn)
player_config.spawn = {
  x = 100,
  y = 100,
}

-- Level system configuration
player_config.level_system = {
  max_level = 50,
  base_exp = 100,
  exp_curve = 1.5,

  -- Stat bonuses per level
  stat_bonuses = {
    max_health = 10,   -- +10 HP per level
    attack_damage = 2, -- +2 damage per level
    speed = 5          -- +5 speed per level
  },

  -- Starting values
  starting_level = 1,
  starting_gold = 0
}

return player_config

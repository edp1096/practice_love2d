-- game/data/player.lua
-- Player configuration (stats, abilities)

local player_config = {}

-- Basic stats
player_config.stats = {
  speed = 300,
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
  sheet = "assets/images/player-sheet.png",
  width = 48,
  height = 48,
  scale = 3,

  -- Draw offsets
  draw_offset_x = -72,
  draw_offset_y = -128,
}

-- Collider
player_config.collider = {
  width = 32,
  height = 32,
  offset_x = 32,
  offset_y = 32,
}

-- Starting position (overridden by map spawn)
player_config.spawn = {
  x = 100,
  y = 100,
}

return player_config

-- game/data/entity_defaults.lua
-- Default entity configurations (used by factory when Tiled properties are missing)

local defaults = {}

defaults.enemy = {
  hp = 100,
  dmg = 10,
  spd = 100,
  atk_cd = 1.0,
  det_rng = 200,
  atk_rng = 50,

  -- Sprite
  spr = "assets/images/sprites/enemies/enemy-sheet-slime-red.png",
  spr_w = 16,
  spr_h = 32,
  spr_scl = 4,

  -- Collider
  col_w = 32,
  col_h = 32,
  col_ox = 0,
  col_oy = 0,

  -- Draw offsets
  draw_ox = -32,
  draw_oy = -112
}

defaults.npc = {
  name = "NPC",
  int_rng = 80,

  -- Sprite
  spr = "assets/images/player/player-sheet.png",
  spr_w = 48,
  spr_h = 48,
  spr_scl = 3,

  -- Collider
  col_w = 32,
  col_h = 32,
  col_ox = 32,
  col_oy = 32,

  -- Draw offsets
  draw_ox = -72,
  draw_oy = -128,

  -- Animation frames
  idle_down = "1-4",
  idle_left = "1-4",
  idle_right = "5-8",
  idle_up = "5-8",
  idle_row_down = 1,
  idle_row_left = 2,
  idle_row_right = 2,
  idle_row_up = 1,

  -- Dialogue
  dlg = "Hello!"
}

return defaults

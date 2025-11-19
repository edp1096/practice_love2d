-- engine/systems/entity_factory.lua
-- Entity creation system (systems layer - no engine dependencies)

local factory = {}

-- Default configs (injected from game)
factory.DEFAULTS = {}

-- Read property with fallback
local function prop(obj, key, default)
  return obj.properties[key] or default
end

-- Create enemy from Tiled object
function factory:createEnemy(obj, enemy_class, map_name)
  -- Extract type from object type field or properties.type (Tiled compatibility)
  local enemy_type = obj.type
  if not enemy_type or enemy_type == "" then
    enemy_type = obj.properties and obj.properties.type
  end

  -- Error if no type specified (map configuration error)
  if not enemy_type or enemy_type == "" then
    error(string.format("Enemy at (%d, %d) has no type specified. Set object type in Tiled.", obj.x, obj.y))
  end

  -- Create unique map_id: "{map_name}_obj_{id}" (e.g., "level1_area1_obj_12")
  map_name = map_name or "unknown"
  local map_id = string.format("%s_obj_%d", map_name, obj.id)

  -- Get respawn property (default: false)
  -- Only enemies with explicit respawn=true will respawn
  local respawn = (obj.properties.respawn == true)

  -- Simple mode: if no custom properties, just use type (loads from types/*.lua)
  local has_custom_props = obj.properties.hp or obj.properties.dmg or obj.properties.spr

  if not has_custom_props then
    -- Simple: just pass type, enemy will load config from types file
    return enemy_class:new(obj.x, obj.y, enemy_type, nil, map_id, respawn)
  end

  -- Advanced mode: create custom config from Tiled properties
  local d = self.DEFAULTS.enemy
  local cfg = {
    sprite_sheet = prop(obj, "spr", d.spr),
    health = prop(obj, "hp", d.hp),
    damage = prop(obj, "dmg", d.dmg),
    speed = prop(obj, "spd", d.spd),
    attack_cooldown = prop(obj, "atk_cd", d.atk_cd),
    detection_range = prop(obj, "det_rng", d.det_rng),
    attack_range = prop(obj, "atk_rng", d.atk_rng),

    sprite_width = prop(obj, "spr_w", d.spr_w),
    sprite_height = prop(obj, "spr_h", d.spr_h),
    sprite_scale = prop(obj, "spr_scl", d.spr_scl),

    collider_width = prop(obj, "col_w", d.col_w),
    collider_height = prop(obj, "col_h", d.col_h),
    collider_offset_x = prop(obj, "col_ox", d.col_ox),
    collider_offset_y = prop(obj, "col_oy", d.col_oy),

    sprite_draw_offset_x = prop(obj, "draw_ox", d.draw_ox),
    sprite_draw_offset_y = prop(obj, "draw_oy", d.draw_oy),
    sprite_origin_x = 0,
    sprite_origin_y = 0,

    -- Color swap (optional)
    source_color = prop(obj, "src_col", nil),
    target_color = prop(obj, "tgt_col", nil)
  }

  return enemy_class:new(obj.x, obj.y, enemy_type, cfg, map_id, respawn)
end

-- Create NPC from Tiled object
function factory:createNPC(obj, npc_class)
  -- Extract type from object type field or properties.type (Tiled compatibility)
  local npc_type = obj.type
  if not npc_type or npc_type == "" then
    npc_type = obj.properties and obj.properties.type
  end

  -- Error if no type specified (map configuration error)
  if not npc_type or npc_type == "" then
    error(string.format("NPC at (%d, %d) has no type specified. Set object type in Tiled.", obj.x, obj.y))
  end

  local npc_id = prop(obj, "id", nil)

  -- Simple mode: if no custom properties, just use type (loads from types/*.lua)
  local has_custom_props = obj.properties.name or obj.properties.dlg or obj.properties.spr

  if not has_custom_props then
    -- Simple: just pass type and id, NPC will load config from types file
    return npc_class:new(obj.x, obj.y, npc_type, npc_id)
  end

  -- Advanced mode: create custom config from Tiled properties
  local d = self.DEFAULTS.npc

  -- Parse dialogue (semicolon-separated)
  local dialogue = prop(obj, "dlg", d.dlg)
  if type(dialogue) == "string" then
    local dlg_table = {}
    for line in dialogue:gmatch("[^;]+") do
      table.insert(dlg_table, line)
    end
    dialogue = dlg_table
  end

  local cfg = {
    name = prop(obj, "name", d.name),
    sprite_sheet = prop(obj, "spr", d.spr),
    dialogue = dialogue,
    dialogue_id = prop(obj, "dialogue_id", nil),  -- For tree-based dialogue
    interaction_range = prop(obj, "int_rng", d.int_rng),

    sprite_width = prop(obj, "spr_w", d.spr_w),
    sprite_height = prop(obj, "spr_h", d.spr_h),
    sprite_scale = prop(obj, "spr_scl", d.spr_scl),

    collider_width = prop(obj, "col_w", d.col_w),
    collider_height = prop(obj, "col_h", d.col_h),
    collider_offset_x = prop(obj, "col_ox", d.col_ox),
    collider_offset_y = prop(obj, "col_oy", d.col_oy),

    sprite_draw_offset_x = prop(obj, "draw_ox", d.draw_ox),
    sprite_draw_offset_y = prop(obj, "draw_oy", d.draw_oy),

    idle_down = prop(obj, "idle_down", d.idle_down),
    idle_left = prop(obj, "idle_left", d.idle_left),
    idle_right = prop(obj, "idle_right", d.idle_right),
    idle_up = prop(obj, "idle_up", d.idle_up),
    idle_row_down = prop(obj, "idle_row_down", d.idle_row_down),
    idle_row_left = prop(obj, "idle_row_left", d.idle_row_left),
    idle_row_right = prop(obj, "idle_row_right", d.idle_row_right),
    idle_row_up = prop(obj, "idle_row_up", d.idle_row_up)
  }

  return npc_class:new(obj.x, obj.y, npc_type, npc_id, cfg)
end

return factory

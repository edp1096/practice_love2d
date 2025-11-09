-- engine/scenes/builder.lua
-- Builds scenes from data configs (no code needed!)

local MenuSceneBase = require "engine.ui.menu.base"
local scene_control = require "engine.core.scene_control"
local save_sys = require "engine.core.save"
local sound = require "engine.core.sound"
local constants = require "engine.core.constants"

local builder = {}

-- Game scene path prefix (injected from main.lua)
builder.game_scene_prefix = "game.scenes."

-- Scene path resolver (try engine first, then game)
local function resolveScenePath(scene_name)
  -- Engine UI screens
  local engine_ui_paths = {
    newgame = "engine.ui.screens.newgame",
    saveslot = "engine.ui.screens.saveslot",
    inventory = "engine.ui.screens.inventory",
    load = "engine.ui.screens.load",
    settings = "engine.ui.screens.settings"
  }

  -- Engine scenes
  local engine_scene_paths = {
    cutscene = "engine.scenes.cutscene",
    gameplay = "engine.scenes.gameplay"
  }

  -- Check engine UI screens first
  if engine_ui_paths[scene_name] then return engine_ui_paths[scene_name] end

  -- Check engine scenes
  if engine_scene_paths[scene_name] then return engine_scene_paths[scene_name] end

  -- Fall back to game scenes (menu, pause, gameover) - uses injected prefix
  return builder.game_scene_prefix .. scene_name
end

-- Execute action from config
local function executeAction(action_cfg, previous_scene)
  if action_cfg.action == "quit" then
    love.event.quit()

  elseif action_cfg.action == "pop_scene" then
    if action_cfg.sfx then
      sound:playSFX(action_cfg.sfx:match("(.+)/"), action_cfg.sfx:match("/(.+)"))
    end
    if action_cfg.resume_bgm then sound:resumeBGM() end
    scene_control.pop()

  elseif action_cfg.action == "push_scene" then
    local scene_path = resolveScenePath(action_cfg.scene)
    local scene = require(scene_path)
    scene_control.push(scene)

  elseif action_cfg.action == "switch_scene" then
    if action_cfg.scene == "cutscene" then
      local cutscene = require "engine.scenes.cutscene"
      scene_control.switch(cutscene,
        "level1",
        constants.GAME_START.DEFAULT_MAP,
        constants.GAME_START.DEFAULT_SPAWN_X,
        constants.GAME_START.DEFAULT_SPAWN_Y,
        1)  -- slot 1
    elseif action_cfg.scene == "newgame" then
      scene_control.switch("newgame")
    elseif action_cfg.scene == "load" then
      scene_control.switch("load")
    else
      local scene_path = resolveScenePath(action_cfg.scene)
      local scene = require(scene_path)
      scene_control.switch(scene)
    end

  elseif action_cfg.action == "start_new_game" then
    -- Start new game (with intro cutscene and is_new_game flag)
    local cutscene = require "engine.scenes.cutscene"
    scene_control.switch(cutscene,
      "level1",
      constants.GAME_START.DEFAULT_MAP,
      constants.GAME_START.DEFAULT_SPAWN_X,
      constants.GAME_START.DEFAULT_SPAWN_Y,
      1,     -- Default to slot 1 (will be saved on first save)
      true)  -- is_new_game = true

  elseif action_cfg.action == "load_recent_save" then
    local recent_slot = save_sys:getMostRecentSlot()
    if recent_slot then
      local save_data = save_sys:loadGame(recent_slot)
      if save_data then
        local gameplay = require "engine.scenes.gameplay"
        scene_control.switch(gameplay, save_data.map, save_data.x, save_data.y, recent_slot, false)  -- is_new_game = false
      else
        sound:playSFX("menu", "error")
      end
    end

  elseif action_cfg.action == "restart_current" then
    local restart_util = require "engine.core.restart"
    local gameplay = require "engine.scenes.gameplay"
    local map, x, y, slot = restart_util:fromCurrentMap(previous_scene)
    scene_control.switch(gameplay, map, x, y, slot, false)  -- is_new_game = false

  elseif action_cfg.action == "restart_from_save" then
    local restart_util = require "engine.core.restart"
    local gameplay = require "engine.scenes.gameplay"
    local map, x, y, slot = restart_util:fromLastSave(previous_scene)
    scene_control.switch(gameplay, map, x, y, slot, false)  -- is_new_game = false
  end
end

-- Build menu scene from config
function builder:buildMenu(cfg)
  -- Dynamic options based on logic
  local function onEnter(self, previous, ...)
    if cfg.options_logic == "has_saves" then
      local has_saves = save_sys:hasSaveFiles()
      self.options = has_saves and cfg.options_with_saves or cfg.options_no_saves
      self.selected = 1
    end

    -- Initialize flash effect if configured
    if cfg.flash and cfg.flash.enabled then
      self.flash_alpha = cfg.flash.initial_alpha or 1.0
      self.flash_speed = cfg.flash.fade_speed or 2.0
      self.flash_color = cfg.flash.color or { 1, 1, 1 }
    end

    -- Play BGM
    if cfg.bgm then sound:playBGM(cfg.bgm, 1.0, true) end
  end

  -- Select handler
  local function onSelect(self, option_index)
    local option_name = self.options[option_index]
    local action = cfg.actions[option_name]
    if action then executeAction(action, self.previous) end
  end

  -- Back handler
  local function onBack(self)
    if cfg.back_action then executeAction(cfg.back_action, self.previous) end
  end

  -- Update handler for flash effect
  local function onUpdate(self, dt)
    if self.flash_alpha and self.flash_alpha > 0 then
      self.flash_alpha = math.max(0, self.flash_alpha - self.flash_speed * dt)
    end
  end

  -- Draw handler for flash effect
  local function onDraw(self)
    if self.flash_alpha and self.flash_alpha > 0 then
      love.graphics.setColor(self.flash_color[1], self.flash_color[2], self.flash_color[3], self.flash_alpha * 0.3)
      love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- Build config with optional flash handlers
  local scene_config = {
    title = cfg.title,
    options = cfg.options or cfg.options_no_saves,
    on_enter = onEnter,  -- Always use onEnter (handles BGM + dynamic options + flash)
    on_select = onSelect,
    on_back = onBack,
    background_scene = cfg.overlay,
    overlay_alpha = cfg.overlay_alpha
  }

  -- Add flash effect handlers if configured
  if cfg.flash and cfg.flash.enabled then
    scene_config.on_update = onUpdate
    scene_config.on_draw = onDraw
  end

  -- Create scene
  return MenuSceneBase:create(scene_config)
end

-- Main builder function
function builder:build(scene_name, scene_configs)
  local cfg = scene_configs[scene_name]
  if not cfg then error("Scene config not found: " .. scene_name) end

  if cfg.type == "menu" then return self:buildMenu(cfg) end

  error("Unknown scene type: " .. cfg.type)
end

return builder

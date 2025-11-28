-- game/setup.lua
-- Game-specific dependency injection and configuration
-- This file configures the engine with game-specific data

local setup = {}

-- Inject all game-specific data into engine modules
function setup.configure()
    -- Load game data
    local entity_types = require "game.data.entities.types"
    local start_config = require "game.data.start"
    local entity_defaults = require "game.data.entities.defaults"
    local player_config = require "game.data.player"
    local cutscene_configs = require "game.data.cutscenes"
    local sound_data = require "game.data.sounds"
    local item_types = require "game.data.items"
    local loot_tables = require "game.data.loot_tables"
    local dialogues = require "game.data.dialogues"  -- Dialogue trees
    local quests = require "game.data.quests"  -- Quest definitions
    local hand_anchors = require "game.data.weapon.hand_anchors"
    local handle_anchors = require "game.data.weapon.handle_anchors"

    -- Load engine modules
    local enemy_class = require "engine.entities.enemy"
    local npc_class = require "engine.entities.npc"
    local weapon_class = require "engine.entities.weapon"
    local item_class = require "engine.entities.item"
    local constants = require "engine.core.constants"
    local factory = require "engine.systems.entity_factory"
    local player_sound = require "engine.entities.player.sound"
    local enemy_sound = require "engine.entities.enemy.sound"
    local gameplay_scene = require "engine.scenes.gameplay"
    local cutscene_scene = require "engine.scenes.cutscene"
    local builder = require "engine.scenes.builder"
    local dialogue = require "engine.ui.dialogue"
    local prompt = require "engine.systems.prompt"
    local quest_system = require "engine.core.quest"

    -- Inject entity type registries
    enemy_class.type_registry = entity_types.enemies
    npc_class.type_registry = entity_types.npcs
    weapon_class.type_registry = entity_types.weapons
    weapon_class.effects_config = entity_types.weapon_effects
    weapon_class.hand_anchors = hand_anchors.HAND_ANCHORS
    weapon_class.handle_anchors = handle_anchors.WEAPON_HANDLE_ANCHORS
    item_class.type_registry = item_types

    -- Inject game start defaults
    constants.GAME_START.DEFAULT_MAP = start_config.map
    constants.GAME_START.DEFAULT_SPAWN_X = start_config.spawn_x
    constants.GAME_START.DEFAULT_SPAWN_Y = start_config.spawn_y
    constants.GAME_START.DEFAULT_INTRO_ID = start_config.intro_id

    -- Inject entity factory defaults
    factory.DEFAULTS = entity_defaults

    -- Inject sound configs
    player_sound.sounds_config = sound_data
    enemy_sound.sounds_config = sound_data

    -- Inject gameplay configs
    gameplay_scene.player_config = player_config
    gameplay_scene.loot_tables = loot_tables
    gameplay_scene.starting_items = start_config.starting_items

    -- Inject cutscene configs
    cutscene_scene.configs = cutscene_configs

    -- Inject game scene path prefix
    builder.game_scene_prefix = "game.scenes."

    -- Inject dialogue reference into prompt (so prompts hide during dialogue)
    prompt.dialogue = dialogue

    -- Inject dialogue trees into dialogue system
    dialogue.dialogue_registry = dialogues

    -- Inject quest system into dialogue (for quest acceptance actions)
    dialogue.quest_system = quest_system

    -- Initialize quest system with quest definitions
    quest_system:registerQuests(quests)

    -- Auto-accept tutorial quest (so it can be completed by talking to NPC)
    quest_system:accept("tutorial_talk")
end

-- Return scene loader function for engine's scene_control
function setup.getSceneLoader()
    return function(scene_name)
        -- Engine UI screens
        local engine_ui_paths = {
            newgame = "engine.ui.screens.newgame",
            saveslot = "engine.ui.screens.saveslot",
            inventory = "engine.ui.screens.inventory",
            questlog = "engine.ui.screens.questlog",
            container = "engine.ui.screens.container",
            load = "engine.ui.screens.load",
            settings = "engine.ui.screens.settings"
        }

        -- Engine scenes
        local engine_scene_paths = {
            cutscene = "engine.scenes.cutscene",
            gameplay = "engine.scenes.gameplay"
        }

        -- Check engine paths first
        if engine_ui_paths[scene_name] then return require(engine_ui_paths[scene_name]) end
        if engine_scene_paths[scene_name] then return require(engine_scene_paths[scene_name]) end

        -- Fall back to game scenes (menu, pause, gameover, ending)
        return require("game.scenes." .. scene_name)
    end
end

return setup

-- engine/scenes/gameplay/scene_setup.lua
-- Gameplay scene initialization (enter/exit/resume/switchMap)
-- Delegates to initializers.lua and map_switch.lua

local scene_setup = {}

-- Sub-modules
local initializers = require "engine.scenes.gameplay.initializers"
local map_switch = require "engine.scenes.gameplay.map_switch"

-- Dependencies for enter function
local camera_sys = require "engine.core.camera"
local save_sys = require "engine.core.save"
local entity_registry = require "engine.core.entity_registry"
local dialogue = require "engine.ui.dialogue"
local quest_system = require "engine.core.quest"
local constants = require "engine.core.constants"
local lighting = require "engine.systems.lighting"

-- Initialize gameplay scene (called from gameplay:enter)
function scene_setup.enter(scene, from_scene, mapPath, spawn_x, spawn_y, save_slot, is_new_game, use_persistence, use_checkpoint)
    -- Initialize lighting system if not already initialized
    if not lighting.canvas then lighting:init() end

    -- Reset camera effects (shake, slow-motion)
    camera_sys:reset()

    mapPath = mapPath or constants.GAME_START.DEFAULT_MAP
    spawn_x = spawn_x or constants.GAME_START.DEFAULT_SPAWN_X
    spawn_y = spawn_y or constants.GAME_START.DEFAULT_SPAWN_Y
    save_slot = save_slot or 1
    if is_new_game == nil then
        is_new_game = false
    end

    scene.current_map_path = mapPath

    -- Store map entry coordinates (for "Restart from Here" functionality)
    scene.map_entry_x = spawn_x
    scene.map_entry_y = spawn_y

    -- Initialize camera
    initializers.initCamera(scene)

    -- Check if we should use checkpoint data (for "Restart from Here")
    local persistence = require "engine.core.persistence"
    local checkpoint = use_checkpoint and persistence:hasCheckpoint() and persistence:getCheckpoint()
    if checkpoint then
        -- Restore entity_registry from checkpoint
        entity_registry.killed_enemies = {}
        entity_registry.picked_items = {}
        entity_registry.transformed_npcs = {}
        entity_registry.destroyed_props = {}
        for k, v in pairs(checkpoint.killed_enemies or {}) do entity_registry.killed_enemies[k] = v end
        for k, v in pairs(checkpoint.picked_items or {}) do entity_registry.picked_items[k] = v end
        for k, v in pairs(checkpoint.transformed_npcs or {}) do entity_registry.transformed_npcs[k] = v end
        for k, v in pairs(checkpoint.destroyed_props or {}) do entity_registry.destroyed_props[k] = v end
        entity_registry.session_map_states = {}

        -- Restore vehicle data from checkpoint
        local entity_registry_data = checkpoint.systems_data.entity_registry or {}
        if entity_registry_data.vehicles then
            entity_registry.vehicles = entity_registry_data.vehicles
            entity_registry.vehicles_initialized = entity_registry_data.vehicles_initialized or false
        end

        -- Load to scene
        entity_registry:loadToScene(scene)

        -- Create save_data from checkpoint
        local player_data = checkpoint.systems_data.player or {}
        local vehicle_data = checkpoint.systems_data.vehicle or {}
        local checkpoint_save_data = {
            hp = player_data.health,
            max_hp = player_data.max_health,
            inventory = checkpoint.systems_data.inventory,
            quest_states = checkpoint.systems_data.quest,
            dialogue_choices = checkpoint.systems_data.dialogue,
            level_data = checkpoint.systems_data.level,
            shop_data = checkpoint.systems_data.shop,
            vehicle_data = vehicle_data,
        }

        scene_setup.initializeFromSaveOrNew(scene, checkpoint_save_data, false, mapPath, spawn_x, spawn_y, save_slot)

    elseif use_persistence and persistence:hasData() then
        -- Restore persistence from global storage (after cutscene transition)
        persistence:loadToScene(scene)

        -- Restore vehicle data from persistence
        local entity_registry_data = persistence:getSystemData("entity_registry") or {}
        if entity_registry_data.vehicles then
            entity_registry.vehicles = entity_registry_data.vehicles
            entity_registry.vehicles_initialized = entity_registry_data.vehicles_initialized or false
        end

        -- Create fake save_data from persistence
        local player_data = persistence:getSystemData("player") or {}
        local vehicle_data = persistence:getSystemData("vehicle") or {}
        local persistence_save_data = {
            hp = player_data.health,
            max_hp = player_data.max_health,
            map = persistence.current_map_path,
            inventory = persistence:getSystemData("inventory"),
            quest_states = persistence:getSystemData("quest"),
            dialogue_choices = persistence:getSystemData("dialogue"),
            level_data = persistence:getSystemData("level"),
            shop_data = persistence:getSystemData("shop"),
            vehicle_data = vehicle_data,
        }

        scene_setup.initializeFromSaveOrNew(scene, persistence_save_data, is_new_game, mapPath, spawn_x, spawn_y, save_slot)
    else
        -- Normal initialization from save data or new game
        local save_data = nil
        if not is_new_game then
            save_data = save_sys:loadGame(save_slot)
        end

        -- Initialize entity_registry
        if is_new_game then
            entity_registry:clear()
            entity_registry:initializeVehiclesFromMaps()
        elseif save_data and save_data.entity_registry then
            entity_registry:import(save_data.entity_registry)
        elseif save_data then
            -- Backward compatibility with old save format
            entity_registry.killed_enemies = save_data.killed_enemies or {}
            entity_registry.picked_items = save_data.picked_items or {}
            entity_registry.transformed_npcs = save_data.transformed_npcs or {}
            entity_registry.destroyed_props = save_data.destroyed_props or {}
            if save_data.vehicle_registry then
                entity_registry.vehicles = save_data.vehicle_registry.vehicles or {}
                entity_registry.vehicles_initialized = save_data.vehicle_registry.initialized or false
            end
        else
            entity_registry:clear()
        end

        -- Load to scene
        entity_registry:loadToScene(scene)

        scene_setup.initializeFromSaveOrNew(scene, save_data, is_new_game, mapPath, spawn_x, spawn_y, save_slot)
    end
end

-- Initialize scene from save data or new game (extracted for reuse)
function scene_setup.initializeFromSaveOrNew(scene, save_data, is_new_game, mapPath, spawn_x, spawn_y, save_slot)
    -- Load or reset dialogue choice history
    if save_data and save_data.dialogue_choices then
        dialogue:importChoiceHistory(save_data.dialogue_choices)
    else
        dialogue:clearChoiceHistory()
        dialogue:clearAllFlags()
    end

    -- Load or reset quest states
    if save_data and save_data.quest_states then
        quest_system:importStates(save_data.quest_states)
    else
        quest_system:resetAll()
    end

    -- Initialize level system
    initializers.initLevelSystem(scene, save_data, is_new_game)

    -- Store quest system reference (for debug display)
    scene.quest_system = quest_system

    -- Create world and player
    initializers.createWorld(scene, mapPath)
    initializers.createPlayer(scene, spawn_x, spawn_y, save_data)

    -- Restore boarded vehicle state from save data
    initializers.restoreVehicles(scene, save_data)

    -- Initialize systems
    initializers.initSystems(scene)
    initializers.initInventory(scene, save_data, is_new_game)

    -- Setup UI and scene state
    initializers.initUI(scene, initializers.setupLighting)
    initializers.initSceneState(scene, save_slot)

    -- Setup callbacks
    initializers.setupCallbacks(scene)

    -- Play BGM
    initializers.startBGM(scene, mapPath)

    -- Save checkpoint for "Restart from Here"
    local persistence = require "engine.core.persistence"
    persistence:saveCheckpoint(scene)
end

-- Delegate to initializers module
scene_setup.initCamera = initializers.initCamera
scene_setup.initLevelSystem = initializers.initLevelSystem
scene_setup.createWorld = initializers.createWorld
scene_setup.createPlayer = initializers.createPlayer
scene_setup.restoreVehicles = initializers.restoreVehicles
scene_setup.initSystems = initializers.initSystems
scene_setup.initInventory = initializers.initInventory
scene_setup.initUI = function(scene) initializers.initUI(scene, initializers.setupLighting) end
scene_setup.initSceneState = initializers.initSceneState
scene_setup.setupCallbacks = initializers.setupCallbacks
scene_setup.startBGM = initializers.startBGM
scene_setup.setupLighting = initializers.setupLighting
scene_setup.exit = initializers.exit
scene_setup.resume = initializers.resume

-- Delegate to map_switch module
scene_setup.switchMap = function(scene, new_map_path, spawn_x, spawn_y)
    map_switch.switchMap(scene, new_map_path, spawn_x, spawn_y, initializers.setupLighting)
end
scene_setup.getLocationId = map_switch.getLocationId

return scene_setup

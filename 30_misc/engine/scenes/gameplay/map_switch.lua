-- engine/scenes/gameplay/map_switch.lua
-- Map switching logic for gameplay scene

local world = require "engine.systems.world"
local entity_registry = require "engine.core.entity_registry"
local enemy_class = require "engine.entities.enemy"
local npc_class = require "engine.entities.npc"
local healing_point_class = require "engine.entities.healing_point"
local world_item_class = require "engine.entities.world_item"
local prop_class = require "engine.entities.prop"
local vehicle_class = require "engine.entities.vehicle"
local dialogue = require "engine.ui.dialogue"
local sound = require "engine.core.sound"
local util = require "engine.utils.util"
local weather = require "engine.systems.weather"
local quest_system = require "engine.core.quest"
local helpers = require "engine.utils.helpers"

local map_switch = {}

-- Helper: Get location ID from map path
local function getLocationId(map_path)
    local level = map_path:match("level(%d+)")
    local area = map_path:match("area(%d+)")

    if level and area then
        return "level" .. level .. "_area" .. area
    end

    return nil
end

-- Save vehicle positions before map switch
local function saveVehiclePositions(scene, current_map_name)
    if not scene.world or not scene.world.vehicles then return end

    for _, vehicle in ipairs(scene.world.vehicles) do
        if vehicle.map_id and not vehicle.is_boarded then
            entity_registry:updateVehiclePosition(
                vehicle.map_id,
                current_map_name,
                vehicle.x,
                vehicle.y,
                vehicle.direction
            )
        end
    end
end

-- Update boarded vehicle to destination map
local function updateBoardedVehiclePosition(boarded_vehicle_map_id, dest_map_name, spawn_x, spawn_y, direction)
    if boarded_vehicle_map_id then
        entity_registry:updateVehiclePosition(
            boarded_vehicle_map_id,
            dest_map_name,
            spawn_x,
            spawn_y,
            direction or "down"
        )
    end
end

-- Handle session state based on map transition type
local function handleSessionStates(current_map_name, current_persist_state, dest_persist_state, scene_world)
    if dest_persist_state then
        -- Entering persist_state=true map (indoor): save current map's session state
        if current_map_name then
            entity_registry:saveSessionState(current_map_name, scene_world)
        end
        -- Don't clear - preserve session states when entering indoor
    elseif current_persist_state then
        -- Leaving persist_state=true map (indoor → outdoor): preserve session states
        -- Don't clear - session states remain for when player returns
    else
        -- Leaving persist_state=false map to persist_state=false map (outdoor → outdoor)
        -- Clear session states only - respawn=true enemies will respawn
        entity_registry:clearSessionStates()
    end
end

-- Sync session map states from scene to entity_registry
local function syncSessionMapStates(scene)
    for k, v in pairs(scene.session_map_states or {}) do
        entity_registry.session_map_states[k] = v
    end
end

-- Create new world after map switch
local function createNewWorld(scene, new_map_path)
    scene.world = world:new(new_map_path, {
        enemy = enemy_class,
        npc = npc_class,
        healing_point = healing_point_class,
        world_item = world_item_class,
        prop = prop_class,
        vehicle = vehicle_class,
        loot_tables = scene.loot_tables,
    })
end

-- Reinitialize player for new map
local function reinitializePlayer(scene, spawn_x, spawn_y)
    scene.player.x = spawn_x
    scene.player.y = spawn_y

    -- CRITICAL: Update player game mode BEFORE adding to world
    scene.player.game_mode = scene.world.game_mode

    -- Apply map-based move mode (walk/run) - reset to config default if not specified
    local map_props = scene.world.map.properties
    local config_default = scene.player_config.animations and scene.player_config.animations.default_move or "walk"
    scene.player.default_move = (map_props and map_props.move_mode) or config_default

    scene.world:addEntity(scene.player)
end

-- Re-board vehicle after map transition
local function reboardVehicle(scene, boarded_vehicle_map_id)
    if not boarded_vehicle_map_id then return end

    for _, vehicle in ipairs(scene.world.vehicles) do
        if vehicle.map_id == boarded_vehicle_map_id then
            scene.player:boardVehicle(vehicle)
            break
        end
    end
end

-- Update systems after map switch
local function updateSystems(scene, new_map_path, setupLightingFunc)
    -- Update minimap for new map
    if scene.minimap then
        scene.minimap:setMap(scene.world)
    end

    -- Update dialogue references
    dialogue.world = scene.world
    dialogue.inventory = scene.inventory

    -- Update lighting for new map
    setupLightingFunc(scene)

    -- Handle BGM based on map properties
    local map_bgm = scene.world.map.properties and scene.world.map.properties.bgm

    if map_bgm then
        sound:playBGM(map_bgm, 1.0, false)
    else
        local level = new_map_path:match("level(%d+)")
        if not level then level = "1" end
        level = "level" .. level
        sound:playBGM(level, 1.0, false)
    end

    -- Reinitialize weather for new map
    weather.camera = scene.cam
    weather:initialize(scene.world.map)
end

-- Update camera for new map
local function updateCamera(scene)
    scene.cam:lookAt(scene.player.x, scene.player.y)

    local mapWidth = scene.world.map.width * scene.world.map.tilewidth
    local mapHeight = scene.world.map.height * scene.world.map.tileheight

    local w, h = util:Get16by9Size(love.graphics.getWidth(), love.graphics.getHeight())
    scene.cam:lockBounds(mapWidth, mapHeight, w, h)
end

-- Switch to a new map
function map_switch.switchMap(scene, new_map_path, spawn_x, spawn_y, setupLightingFunc)
    -- Get destination map name for registry update
    local dest_map_data = love.filesystem.load(new_map_path)()
    local dest_map_name = dest_map_data and dest_map_data.properties and dest_map_data.properties.name or "unknown"

    -- Save boarded vehicle info BEFORE destroying world
    local boarded_vehicle_map_id = nil
    if scene.player.is_boarded and scene.player.boarded_vehicle then
        boarded_vehicle_map_id = scene.player.boarded_vehicle.map_id
        scene.player:disembark()
    end

    -- CRITICAL: Sync persistence data from world BEFORE destroying it
    helpers.syncPersistenceData(scene)

    -- Get current map properties
    local current_map_props = scene.world and scene.world.map and scene.world.map.properties
    local current_map_name = current_map_props and current_map_props.name
    local current_persist_state = current_map_props and current_map_props.persist_state
    local dest_persist_state = dest_map_data and dest_map_data.properties and dest_map_data.properties.persist_state

    -- Save vehicle positions in current map
    saveVehiclePositions(scene, current_map_name)

    -- Update boarded vehicle to destination map
    updateBoardedVehiclePosition(boarded_vehicle_map_id, dest_map_name, spawn_x, spawn_y, scene.player.direction)

    -- Handle session states based on map transition type
    handleSessionStates(current_map_name, current_persist_state, dest_persist_state, scene.world)

    -- Sync session map states
    syncSessionMapStates(scene)

    -- Clean up old colliders BEFORE destroying world
    helpers.destroyColliders(scene.player)

    -- Now destroy world
    if scene.world then scene.world:destroy() end
    weather:cleanup()

    scene.current_map_path = new_map_path

    -- Update map entry coordinates for "Restart from Here"
    scene.map_entry_x = spawn_x
    scene.map_entry_y = spawn_y

    -- Track location for explore quests
    local location_id = getLocationId(new_map_path)
    if location_id then
        quest_system:onLocationVisited(location_id)
    end

    -- Sync from scene to entity_registry before creating new world
    entity_registry:syncFromWorld(scene.world)

    -- Create new world
    createNewWorld(scene, new_map_path)

    -- Reinitialize player
    reinitializePlayer(scene, spawn_x, spawn_y)

    -- Re-board vehicle if needed
    reboardVehicle(scene, boarded_vehicle_map_id)

    -- Update systems
    updateSystems(scene, new_map_path, setupLightingFunc)

    -- Update camera
    updateCamera(scene)

    -- Reset transition state
    scene.transition_cooldown = 0.5
    scene.fade_alpha = 1.0
    scene.is_fading = true

    -- Save checkpoint for "Restart from Here"
    local persistence = require "engine.core.persistence"
    persistence:saveCheckpoint(scene)
end

-- Export getLocationId for external use
map_switch.getLocationId = getLocationId

return map_switch

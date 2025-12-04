-- engine/core/persistence.lua
-- Global persistence storage for scene transitions
-- Extensible system: register new systems with registerSystem()

local utils = require "engine.utils.util"

local persistence = {
    -- Core persistence data (world state)
    killed_enemies = {},
    picked_items = {},
    transformed_npcs = {},
    destroyed_props = {},
    session_map_states = {},

    -- Current game state
    current_save_slot = 1,
    current_map_path = nil,

    -- Dynamic storage for registered systems
    systems_data = {},

    -- Registered systems (name -> {save=fn, load=fn})
    registered_systems = {},

    -- Checkpoint data (saved on map entry for "Restart from Here")
    checkpoint = nil,
}

-- Tables that need to be persisted
local PERSISTENCE_TABLES = {
    "killed_enemies",
    "picked_items",
    "transformed_npcs",
    "destroyed_props",
    "session_map_states",
}

-- Register a system for automatic save/load
-- save_fn(scene) -> returns serializable data
-- load_fn(scene, data) -> restores state from data
function persistence:registerSystem(name, save_fn, load_fn)
    self.registered_systems[name] = {
        save = save_fn,
        load = load_fn,
    }
end

-- Save current scene's persistence data
function persistence:saveFromScene(scene)
    if not scene then return end

    -- Sync from world first
    local helpers = require "engine.utils.helpers"
    helpers.syncPersistenceData(scene)

    -- Copy core world state
    for _, table_name in ipairs(PERSISTENCE_TABLES) do
        self[table_name] = utils:ShallowCopy(scene[table_name] or {})
    end

    self.current_save_slot = scene.current_save_slot
    self.current_map_path = scene.current_map_path

    -- Save all registered systems
    self.systems_data = {}
    for name, system in pairs(self.registered_systems) do
        if system.save then
            self.systems_data[name] = system.save(scene)
        end
    end
end

-- Load persistence data into scene
function persistence:loadToScene(scene)
    if not scene then return end

    -- Copy core world state
    for _, table_name in ipairs(PERSISTENCE_TABLES) do
        scene[table_name] = utils:ShallowCopy(self[table_name] or {})
    end
end

-- Get saved data for a registered system (for scene_setup to build persistence_save_data)
function persistence:getSystemData(name)
    return self.systems_data[name]
end

-- Check if we have saved persistence data
function persistence:hasData()
    return next(self.killed_enemies) ~= nil or
           next(self.picked_items) ~= nil or
           next(self.transformed_npcs) ~= nil or
           next(self.destroyed_props) ~= nil or
           next(self.systems_data) ~= nil
end

-- Clear all persistence data (for new game)
function persistence:clear()
    self.killed_enemies = {}
    self.picked_items = {}
    self.transformed_npcs = {}
    self.destroyed_props = {}
    self.session_map_states = {}
    self.current_save_slot = 1
    self.current_map_path = nil
    self.systems_data = {}
    self.checkpoint = nil
end

-- ============================================
-- CHECKPOINT SYSTEM (for "Restart from Here")
-- Saves state on map entry, restores on death
-- ============================================

-- Save checkpoint when entering a map
function persistence:saveCheckpoint(scene)
    if not scene then return end

    -- Sync from world first
    local helpers = require "engine.utils.helpers"
    helpers.syncPersistenceData(scene)

    self.checkpoint = {
        -- Map info
        map_path = scene.current_map_path,
        spawn_x = scene.map_entry_x,
        spawn_y = scene.map_entry_y,
        save_slot = scene.current_save_slot,

        -- Systems data
        systems_data = {},
    }

    -- Copy world state (excluding session_map_states for checkpoint)
    for _, table_name in ipairs(PERSISTENCE_TABLES) do
        if table_name ~= "session_map_states" then
            self.checkpoint[table_name] = utils:ShallowCopy(scene[table_name] or {})
        end
    end

    -- Save all registered systems
    for name, system in pairs(self.registered_systems) do
        if system.save then
            self.checkpoint.systems_data[name] = system.save(scene)
        end
    end
end

-- Check if checkpoint exists
function persistence:hasCheckpoint()
    return self.checkpoint ~= nil
end

-- Get checkpoint data
function persistence:getCheckpoint()
    return self.checkpoint
end

-- Clear checkpoint only
function persistence:clearCheckpoint()
    self.checkpoint = nil
end

-- ============================================
-- Register built-in systems
-- ============================================

-- Player system
persistence:registerSystem("player", function(scene)
    if scene.player then
        return {
            health = scene.player.health,
            max_health = scene.player.max_health,
        }
    end
    return nil
end, nil)  -- load handled in scene_setup

-- Inventory system
persistence:registerSystem("inventory", function(scene)
    if scene.inventory then
        return scene.inventory:save()
    end
    return nil
end, nil)

-- Quest system
persistence:registerSystem("quest", function(scene)
    local quest_system = require "engine.core.quest"
    return quest_system:exportStates()
end, nil)

-- Dialogue system
persistence:registerSystem("dialogue", function(scene)
    local dialogue = require "engine.ui.dialogue"
    return dialogue:exportChoiceHistory()
end, nil)

-- Level system (exp, gold, etc.)
persistence:registerSystem("level", function(scene)
    local level_system = require "engine.core.level"
    return level_system:serialize()
end, nil)

-- Shop system (stock changes)
persistence:registerSystem("shop", function(scene)
    local shop_system = require "engine.systems.shop"
    return shop_system:serialize()
end, nil)

-- Vehicle system (vehicle state across level transitions)
persistence:registerSystem("vehicle", function(scene)
    local vehicle_data = {
        is_boarded = scene.player and scene.player.is_boarded or false,
        boarded_type = nil,
        vehicles = {}
    }

    -- Save boarded vehicle type
    if scene.player and scene.player.is_boarded and scene.player.boarded_vehicle then
        vehicle_data.boarded_type = scene.player.boarded_vehicle.type
    end

    -- Save all vehicles in current world
    if scene.world and scene.world.vehicles then
        for _, vehicle in ipairs(scene.world.vehicles) do
            table.insert(vehicle_data.vehicles, {
                x = vehicle.x,
                y = vehicle.y,
                type = vehicle.type,
                map_id = vehicle.map_id,
                direction = vehicle.direction,
                is_boarded = vehicle.is_boarded
            })
        end
    end

    return vehicle_data
end, nil)

return persistence

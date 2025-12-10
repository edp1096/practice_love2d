-- engine/core/persistence.lua
-- Global persistence storage for scene transitions
-- Extensible system: register new systems with registerSystem()
-- Now delegates entity state to entity_registry

local utils = require "engine.utils.util"
local entity_registry = require "engine.core.entity_registry"

local persistence = {
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

-- Legacy: Tables that were persisted (now handled by entity_registry)
-- Kept for backward compatibility with existing save files
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

    -- Sync to entity_registry (single source of truth)
    entity_registry:syncFromWorld(scene.world)

    -- Copy session_map_states to entity_registry
    for k, v in pairs(scene.session_map_states or {}) do
        entity_registry.session_map_states[k] = v
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

    -- Load from entity_registry (single source of truth)
    entity_registry:loadToScene(scene)
end

-- Get saved data for a registered system (for scene_setup to build persistence_save_data)
function persistence:getSystemData(name)
    return self.systems_data[name]
end

-- Check if we have saved persistence data
function persistence:hasData()
    return next(entity_registry.killed_enemies) ~= nil or
           next(entity_registry.picked_items) ~= nil or
           next(entity_registry.transformed_npcs) ~= nil or
           next(entity_registry.destroyed_props) ~= nil or
           next(self.systems_data) ~= nil
end

-- Clear all persistence data (for new game)
function persistence:clear()
    entity_registry:clear()
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

    -- Sync to entity_registry
    entity_registry:syncFromWorld(scene.world)

    self.checkpoint = {
        -- Map info
        map_path = scene.current_map_path,
        spawn_x = scene.map_entry_x,
        spawn_y = scene.map_entry_y,
        save_slot = scene.current_save_slot,

        -- Entity state from registry
        killed_enemies = utils:ShallowCopy(entity_registry.killed_enemies),
        picked_items = utils:ShallowCopy(entity_registry.picked_items),
        transformed_npcs = utils:ShallowCopy(entity_registry.transformed_npcs),
        destroyed_props = utils:ShallowCopy(entity_registry.destroyed_props),

        -- Systems data
        systems_data = {},
    }

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

-- Vehicle system (boarded state for transitions)
-- Note: entity_registry handles all vehicle positions now
persistence:registerSystem("vehicle", function(scene)
    local vehicle_data = {
        is_boarded = scene.player and scene.player.is_boarded or false,
        boarded_map_id = nil,
    }

    -- Save boarded vehicle map_id
    if scene.player and scene.player.is_boarded and scene.player.boarded_vehicle then
        vehicle_data.boarded_map_id = scene.player.boarded_vehicle.map_id
    end

    -- Sync current world vehicles to registry
    if scene.world and scene.world.vehicles then
        local map_name = scene.world.map and scene.world.map.properties
                         and scene.world.map.properties.name or "unknown"
        for _, vehicle in ipairs(scene.world.vehicles) do
            if vehicle.map_id and not vehicle.is_boarded then
                entity_registry:updateVehiclePosition(
                    vehicle.map_id,
                    map_name,
                    vehicle.x,
                    vehicle.y,
                    vehicle.direction
                )
            end
        end
    end

    return vehicle_data
end, nil)

-- Entity registry system (exports all entity state for save/load)
persistence:registerSystem("entity_registry", function(scene)
    return entity_registry:export()
end, nil)

return persistence

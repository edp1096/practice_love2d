-- engine/core/entity_registry.lua
-- Unified entity state registry: Single Source of Truth for all entity persistence
-- Consolidates: vehicle_registry, killed_enemies, picked_items, transformed_npcs, destroyed_props

local entity_registry = {
    -- Vehicle states: { [map_id] = { type, original_map, current_map, x, y, direction } }
    vehicles = {},
    vehicles_initialized = false,

    -- Killed enemies (permanent deaths only, respawn=false)
    -- { [map_id] = true }
    killed_enemies = {},

    -- Picked items (permanent pickups only, respawn=false)
    -- { [map_id] = true }
    picked_items = {},

    -- Transformed NPCs (NPC<->Enemy conversions)
    -- { [map_id] = { enemy_type/npc_type, original_npc_type, x, y, facing, map_name } }
    transformed_npcs = {},

    -- Destroyed props (permanent destroys only, respawn=false)
    -- { [map_id] = true }
    destroyed_props = {},

    -- Session-based map states (preserved when entering persist_state=true maps)
    -- { [map_name] = { killed_enemies = {}, picked_items = {}, destroyed_props = {} } }
    session_map_states = {},
}

-- ===========================================
-- Generic state management
-- ===========================================

-- Get state for an entity type
function entity_registry:get(entity_type, map_id)
    local storage = self[entity_type]
    if storage and map_id then
        return storage[map_id]
    end
    return storage
end

-- Set state for an entity type
function entity_registry:set(entity_type, map_id, value)
    if self[entity_type] then
        self[entity_type][map_id] = value
    end
end

-- Check if an entity exists in storage
function entity_registry:has(entity_type, map_id)
    return self[entity_type] and self[entity_type][map_id] ~= nil
end

-- Remove an entity from storage
function entity_registry:remove(entity_type, map_id)
    if self[entity_type] then
        self[entity_type][map_id] = nil
    end
end

-- ===========================================
-- Vehicle-specific methods (migrated from vehicle_registry)
-- ===========================================

-- Register a vehicle (called during initial Tiled load)
function entity_registry:registerVehicle(map_id, vehicle_data)
    self.vehicles[map_id] = {
        type = vehicle_data.type,
        original_map = vehicle_data.original_map,
        current_map = vehicle_data.current_map or vehicle_data.original_map,
        x = vehicle_data.x,
        y = vehicle_data.y,
        direction = vehicle_data.direction or "down",
    }
end

-- Update vehicle position (called when vehicle moves or player disembarks)
function entity_registry:updateVehiclePosition(map_id, current_map, x, y, direction)
    if self.vehicles[map_id] then
        self.vehicles[map_id].current_map = current_map
        self.vehicles[map_id].x = x
        self.vehicles[map_id].y = y
        self.vehicles[map_id].direction = direction or self.vehicles[map_id].direction
    end
end

-- Get all vehicles for a specific map
function entity_registry:getVehiclesForMap(map_name)
    local result = {}
    for map_id, data in pairs(self.vehicles) do
        if data.current_map == map_name then
            result[map_id] = data
        end
    end
    return result
end

-- Check if vehicle registry is initialized
function entity_registry:isVehiclesInitialized()
    return self.vehicles_initialized
end

-- Mark vehicles as initialized
function entity_registry:markVehiclesInitialized()
    self.vehicles_initialized = true
end

-- Initialize vehicles from all maps (called on new game start)
function entity_registry:initializeVehiclesFromMaps()
    self.vehicles = {}
    self.vehicles_initialized = false

    local utils = require "engine.utils.util"
    local map_list = utils:scanFiles("assets/maps", "%.lua")

    for _, map_path in ipairs(map_list) do
        local success, map_data = pcall(function()
            return love.filesystem.load(map_path)()
        end)

        if success and map_data then
            local map_name = map_data.properties and map_data.properties.name or "unknown"

            for _, layer in ipairs(map_data.layers or {}) do
                if layer.name == "Vehicles" and layer.objects then
                    for _, obj in ipairs(layer.objects) do
                        local vehicle_type = obj.type
                        if not vehicle_type or vehicle_type == "" then
                            vehicle_type = obj.properties and obj.properties.type
                        end
                        if not vehicle_type or vehicle_type == "" then
                            vehicle_type = "horse"
                        end

                        local map_id = string.format("%s_vehicle_%d", map_name, obj.id)
                        local center_x = obj.x + (obj.width or 0) / 2
                        local center_y = obj.y + (obj.height or 0) / 2

                        self:registerVehicle(map_id, {
                            type = vehicle_type,
                            original_map = map_name,
                            current_map = map_name,
                            x = center_x,
                            y = center_y,
                            direction = "down",
                        })
                    end
                end
            end
        end
    end

    self.vehicles_initialized = true
end

-- ===========================================
-- Session state management
-- ===========================================

-- Save current map's session state (when entering persist_state=true map)
function entity_registry:saveSessionState(map_name, world)
    if not map_name or not world then return end

    local session_state = self.session_map_states[map_name] or {
        killed_enemies = {},
        picked_items = {},
        destroyed_props = {}
    }

    -- Merge all killed enemies for this map
    for map_id, _ in pairs(world.session_killed_enemies or {}) do
        if map_id:find("^" .. map_name .. "_") then
            session_state.killed_enemies[map_id] = true
        end
    end

    -- Merge all picked items for this map
    for map_id, _ in pairs(world.session_picked_items or {}) do
        if map_id:find("^" .. map_name .. "_") then
            session_state.picked_items[map_id] = true
        end
    end

    -- Merge all destroyed props for this map
    for map_id, _ in pairs(world.session_destroyed_props or {}) do
        if map_id:find("^" .. map_name .. "_") then
            session_state.destroyed_props[map_id] = true
        end
    end

    self.session_map_states[map_name] = session_state
end

-- Get merged persistence data (permanent + session)
function entity_registry:getMergedData()
    local merged = {
        killed_enemies = {},
        picked_items = {},
        destroyed_props = {}
    }

    -- Copy permanent data
    for k, v in pairs(self.killed_enemies) do merged.killed_enemies[k] = v end
    for k, v in pairs(self.picked_items) do merged.picked_items[k] = v end
    for k, v in pairs(self.destroyed_props) do merged.destroyed_props[k] = v end

    -- Merge session data
    for _, state in pairs(self.session_map_states) do
        for map_id, _ in pairs(state.killed_enemies or {}) do
            merged.killed_enemies[map_id] = true
        end
        for map_id, _ in pairs(state.picked_items or {}) do
            merged.picked_items[map_id] = true
        end
        for map_id, _ in pairs(state.destroyed_props or {}) do
            merged.destroyed_props[map_id] = true
        end
    end

    return merged
end

-- Clear session states only (outdoor -> outdoor transition)
function entity_registry:clearSessionStates()
    self.session_map_states = {}
end

-- ===========================================
-- Bulk operations
-- ===========================================

-- Clear all data (for new game)
function entity_registry:clear()
    self.vehicles = {}
    self.vehicles_initialized = false
    self.killed_enemies = {}
    self.picked_items = {}
    self.transformed_npcs = {}
    self.destroyed_props = {}
    self.session_map_states = {}
end

-- Export all data for saving
function entity_registry:export()
    return {
        vehicles = self.vehicles,
        vehicles_initialized = self.vehicles_initialized,
        killed_enemies = self.killed_enemies,
        picked_items = self.picked_items,
        transformed_npcs = self.transformed_npcs,
        destroyed_props = self.destroyed_props,
        -- Note: session_map_states are not saved (session-only)
    }
end

-- Import data from save file
function entity_registry:import(data)
    if not data then return end

    self.vehicles = data.vehicles or {}
    self.vehicles_initialized = data.vehicles_initialized or false
    self.killed_enemies = data.killed_enemies or {}
    self.picked_items = data.picked_items or {}
    self.transformed_npcs = data.transformed_npcs or {}
    self.destroyed_props = data.destroyed_props or {}
    self.session_map_states = {}  -- Always start fresh for session
end

-- Sync from world (after world updates)
function entity_registry:syncFromWorld(world)
    if not world then return end

    -- Merge new permanent kills from world
    for k, v in pairs(world.killed_enemies or {}) do
        self.killed_enemies[k] = v
    end

    -- Merge new permanent picks from world
    for k, v in pairs(world.picked_items or {}) do
        self.picked_items[k] = v
    end

    -- Merge new permanent destroys from world
    for k, v in pairs(world.destroyed_props or {}) do
        self.destroyed_props[k] = v
    end

    -- Sync transformed NPCs (complete replacement as world has latest)
    for k, v in pairs(world.transformed_npcs or {}) do
        self.transformed_npcs[k] = v
    end
end

-- Load data into scene (for scene initialization)
function entity_registry:loadToScene(scene)
    if not scene then return end

    -- Copy data to scene (shallow copy to avoid reference issues)
    scene.picked_items = {}
    scene.killed_enemies = {}
    scene.transformed_npcs = {}
    scene.destroyed_props = {}
    scene.session_map_states = {}

    for k, v in pairs(self.picked_items) do scene.picked_items[k] = v end
    for k, v in pairs(self.killed_enemies) do scene.killed_enemies[k] = v end
    for k, v in pairs(self.transformed_npcs) do scene.transformed_npcs[k] = v end
    for k, v in pairs(self.destroyed_props) do scene.destroyed_props[k] = v end
    for k, v in pairs(self.session_map_states) do scene.session_map_states[k] = v end
end

return entity_registry

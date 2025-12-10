-- engine/scenes/gameplay/save_manager.lua
-- Save/load game state management

local save_manager = {}

local save_sys = require "engine.core.save"
local sound = require "engine.core.sound"
local dialogue = require "engine.ui.dialogue"
local quest_system = require "engine.core.quest"
local level_system = require "engine.core.level"
local shop_system = require "engine.systems.shop"
local entity_registry = require "engine.core.entity_registry"
local helpers = require "engine.utils.helpers"

-- Collect vehicle boarded state for saving
local function collectVehicleData(scene)
    local vehicle_data = {
        is_boarded = scene.player.is_boarded or false,
        boarded_map_id = nil,  -- map_id of boarded vehicle (for restore)
    }

    -- Save boarded vehicle map_id
    if scene.player.is_boarded and scene.player.boarded_vehicle then
        vehicle_data.boarded_map_id = scene.player.boarded_vehicle.map_id
    end

    return vehicle_data
end

-- Sync vehicle positions to entity_registry before saving
local function syncVehicleRegistryBeforeSave(scene)
    if not scene.world or not scene.world.vehicles then
        return
    end

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

-- Save current game state to slot
function save_manager.saveGame(scene, slot)
    slot = slot or scene.current_save_slot or 1

    -- Sync persistence data from world (world may have updates that scene doesn't have)
    helpers.syncPersistenceData(scene)

    -- Sync vehicle positions to registry before saving
    syncVehicleRegistryBeforeSave(scene)

    -- Sync from world to entity_registry
    entity_registry:syncFromWorld(scene.world)

    -- Save using entity_registry (Single Source of Truth)
    local save_data = {
        hp = scene.player.health,
        max_hp = scene.player.max_health,
        map = scene.current_map_path,
        x = scene.player.x,
        y = scene.player.y,
        inventory = scene.inventory and scene.inventory:save() or nil,
        dialogue_choices = dialogue:exportChoiceHistory(),
        quest_states = quest_system:exportStates(),
        level_data = level_system:serialize(),
        shop_data = shop_system:serialize(),
        vehicle_data = collectVehicleData(scene),
        entity_registry = entity_registry:export(),  -- Single Source of Truth for all entity state
    }

    local success = save_sys:saveGame(slot, save_data)
    if success then
        scene.current_save_slot = slot
        save_manager.showSaveNotification(scene)

        sound:playSFX("ui", "save")
    end
end

-- Show save notification
function save_manager.showSaveNotification(scene)
    scene.save_notification.active = true
    scene.save_notification.timer = scene.save_notification.duration
end

return save_manager

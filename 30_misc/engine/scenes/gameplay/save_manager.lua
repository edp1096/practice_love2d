-- engine/scenes/gameplay/save_manager.lua
-- Save/load game state management

local save_manager = {}

local save_sys = require "engine.core.save"
local sound = require "engine.core.sound"
local dialogue = require "engine.ui.dialogue"
local quest_system = require "engine.core.quest"
local level_system = require "engine.core.level"
local shop_system = require "engine.systems.shop"
local helpers = require "engine.utils.helpers"

-- Collect vehicle state data for saving
local function collectVehicleData(scene)
    local vehicle_data = {
        is_boarded = scene.player.is_boarded or false,
        boarded_type = nil,
        vehicles = {}  -- All vehicles in current map (position, type, state)
    }

    -- Save boarded vehicle type
    if scene.player.is_boarded and scene.player.boarded_vehicle then
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
end

-- Save current game state to slot
function save_manager.saveGame(scene, slot)
    slot = slot or scene.current_save_slot or 1

    -- Sync persistence data from world (world may have updates that scene doesn't have)
    helpers.syncPersistenceData(scene)

    -- Save killed_enemies (permanent deaths - respawn=false enemies)
    -- respawn=true enemies will respawn on load (not in killed_enemies)
    local save_data = {
        hp = scene.player.health,
        max_hp = scene.player.max_health,
        map = scene.current_map_path,
        x = scene.player.x,
        y = scene.player.y,
        inventory = scene.inventory and scene.inventory:save() or nil,
        picked_items = scene.picked_items or {},
        killed_enemies = scene.killed_enemies or {},  -- Permanent deaths only
        destroyed_props = scene.destroyed_props or {},  -- Permanent prop destroys only
        transformed_npcs = scene.transformed_npcs or {},
        dialogue_choices = dialogue:exportChoiceHistory(),
        quest_states = quest_system:exportStates(),
        level_data = level_system:serialize(),
        shop_data = shop_system:serialize(),
        vehicle_data = collectVehicleData(scene),
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

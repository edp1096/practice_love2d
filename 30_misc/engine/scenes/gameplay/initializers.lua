-- engine/scenes/gameplay/initializers.lua
-- Individual initialization functions for gameplay scene

local player_module = require "engine.entities.player"
local world_sys = require "engine.systems.world"
local camera = require "vendor.hump.camera"
local display = require "engine.core.display"
local enemy_class = require "engine.entities.enemy"
local npc_class = require "engine.entities.npc"
local healing_point_class = require "engine.entities.healing_point"
local world_item_class = require "engine.entities.world_item"
local prop_class = require "engine.entities.prop"
local vehicle_class = require "engine.entities.vehicle"
local item_class = require "engine.entities.item"
local dialogue = require "engine.ui.dialogue"
local sound = require "engine.core.sound"
local constants = require "engine.core.constants"
local minimap_class = require "engine.systems.hud.minimap"
local lighting = require "engine.systems.lighting"
local weather = require "engine.systems.weather"
local quest_system = require "engine.core.quest"
local level_system = require "engine.core.level"
local inventory_class = require "engine.systems.inventory"

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

local initializers = {}

-- Light configuration constants
initializers.LIGHT_CONFIGS = {
    player = {
        radius = 250,
        color = {1, 0.9, 0.7},
        intensity = 1.0
    },
    enemy = {
        radius = 100,
        color = {1, 0.4, 0.4},
        intensity = 0.6
    },
    npc = {
        radius = 120,
        color = {0.8, 0.9, 1.0},
        intensity = 0.7
    },
    savepoint = {
        radius = 150,
        color = {0.3, 1.0, 0.5},
        intensity = 0.8,
        flicker = true,
        flicker_speed = 3.0,
        flicker_amount = 0.2
    }
}

-- Helper: Get entity center position
local function getEntityCenter(entity)
    return entity.x + entity.collider_offset_x,
           entity.y + entity.collider_offset_y
end

-- Helper: Add light to entity with given config
local function addEntityLight(entity, config, x, y)
    return lighting:addLight({
        type = "point",
        x = x or entity.x,
        y = y or entity.y,
        radius = config.radius,
        color = config.color,
        intensity = config.intensity,
        flicker = config.flicker,
        flicker_speed = config.flicker_speed,
        flicker_amount = config.flicker_amount
    })
end

-- Initialize camera
function initializers.initCamera(scene)
    local vw, vh = display:GetVirtualDimensions()
    local sw, sh = display:GetScreenDimensions()
    local scale_x = sw / vw
    local scale_y = sh / vh
    local cam_scale = math.min(scale_x, scale_y) * constants.CAMERA.ZOOM_FACTOR

    scene.cam = camera(0, 0, cam_scale, 0, 0)
end

-- Initialize level system
function initializers.initLevelSystem(scene, save_data, is_new_game)
    local level_config = scene.player_config.level_system
    if level_config then
        level_system:init(level_config)
    else
        level_system:init()
    end

    -- Load level system data from save or reset
    if save_data and save_data.level_data then
        level_system:deserialize(save_data.level_data)
    else
        level_system:reset()
    end

    -- Load shop system data from save or reset
    local shop_system = require "engine.systems.shop"
    if save_data and save_data.shop_data then
        shop_system:deserialize(save_data.shop_data)
    else
        shop_system:reset()
    end
end

-- Create world
function initializers.createWorld(scene, mapPath)
    scene.world = world_sys:new(mapPath, {
        enemy = enemy_class,
        npc = npc_class,
        healing_point = healing_point_class,
        world_item = world_item_class,
        prop = prop_class,
        vehicle = vehicle_class,
        loot_tables = scene.loot_tables
    })
end

-- Create player
function initializers.createPlayer(scene, spawn_x, spawn_y, save_data)
    scene.player = player_module:new(spawn_x, spawn_y, scene.player_config)

    -- Set player game mode based on world
    scene.player.game_mode = scene.world.game_mode

    -- Apply map-based move mode (walk/run) - for indoor maps etc.
    local map_props = scene.world.map.properties
    if map_props then
        if map_props.move_mode then
            scene.player.default_move = map_props.move_mode
        end
        if map_props.walk_speed then
            scene.player.walk_speed = tonumber(map_props.walk_speed)
        end
    end

    -- Apply loaded save data
    if save_data and save_data.hp then
        scene.player.health = save_data.hp
        scene.player.max_health = save_data.max_hp
    end

    scene.world:addEntity(scene.player)
end

-- Restore boarded vehicle from save data
function initializers.restoreVehicles(scene, save_data)
    if not save_data or not save_data.vehicle_data then
        return
    end

    local vehicle_data = save_data.vehicle_data

    -- Only restore boarded state - positions are handled by vehicle_registry
    if vehicle_data.is_boarded and vehicle_data.boarded_map_id then
        for _, vehicle in ipairs(scene.world.vehicles) do
            if vehicle.map_id == vehicle_data.boarded_map_id then
                scene.player:boardVehicle(vehicle, true)  -- silent = true (loading)
                break
            end
        end
    end
end

-- Initialize minimap and weather
function initializers.initSystems(scene)
    scene.minimap = minimap_class:new()
    scene.minimap:setMap(scene.world)

    weather.camera = scene.cam
    weather:initialize(scene.world.map)
end

-- Initialize inventory
function initializers.initInventory(scene, save_data, is_new_game)
    scene.inventory = inventory_class:new(item_class)

    -- Load inventory from save data
    if save_data and save_data.inventory then
        scene.inventory:load(save_data.inventory)

        -- Apply equipped weapon to player
        local weapon_item_id = scene.inventory.equipment_slots["weapon"]
        if weapon_item_id then
            local weapon_data = scene.inventory.items[weapon_item_id]
            if weapon_data and weapon_data.item.weapon_type then
                scene.player:equipWeapon(weapon_data.item.weapon_type)
            end
        end

        -- Apply equipped items' stats to player
        for slot_name, item_id in pairs(scene.inventory.equipment_slots) do
            local item_data = scene.inventory.items[item_id]
            if item_data and item_data.item.stats then
                scene.player:applyEquipmentStats(item_data.item.stats)
            end
        end
    else
        -- Give starting items
        for _, item_config in ipairs(scene.starting_items) do
            scene.inventory:addItem(item_config.type, item_config.quantity)
        end
    end

    -- Inject inventory reference into quest system
    quest_system.inventory = scene.inventory

    -- Auto-accept tutorial quest for new game
    if is_new_game then
        quest_system:accept("tutorial_talk")
    end
end

-- Initialize UI (dialogue, lighting, input)
function initializers.initUI(scene, setupLightingFunc)
    dialogue:initialize(display)

    -- Inject world and inventory references into dialogue
    dialogue.world = scene.world
    dialogue.inventory = scene.inventory

    -- Initialize lighting
    setupLightingFunc(scene)

    -- Show virtual gamepad for mobile gameplay
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        if not virtual_gamepad.enabled then
            virtual_gamepad:init()
        end
        virtual_gamepad:show()
    end

    -- Set game context for input coordinator
    local input = require "engine.core.input"
    input:setGameContext({
        player = scene.player,
        world = scene.world
    })

    -- Set scene context for input priority
    input:setSceneContext("gameplay")
end

-- Initialize scene state
function initializers.initSceneState(scene, save_slot)
    scene.current_save_slot = save_slot
    scene.transition_cooldown = 0

    scene.fade_alpha = 1.0
    scene.fade_speed = 2.0
    scene.is_fading = true

    scene.save_notification = {
        active = false,
        timer = 0,
        duration = 2.0,
        text = "Game Saved!"
    }

    -- Track gamepad skip button state
    scene.skip_button_held = false

    -- Track selected quickslot for gamepad (1-5)
    scene.selected_quickslot = 1
    scene.last_selected_quickslot = nil
end

-- Setup system callbacks
function initializers.setupCallbacks(scene)
    -- Setup level system callbacks
    level_system.callbacks.on_level_up = function(new_level, stat_bonuses)
        if stat_bonuses.max_health then
            scene.player.max_health = scene.player.max_health + stat_bonuses.max_health
            scene.player.health = math.min(scene.player.health + stat_bonuses.max_health, scene.player.max_health)
        end

        if stat_bonuses.speed then
            scene.player.speed = scene.player.speed + stat_bonuses.speed
        end
    end

    -- Setup quest system callbacks
    quest_system.callbacks.on_quest_completed = function(quest_id)
        -- Quest completed (objectives done, ready to turn in)
    end

    quest_system.callbacks.on_quest_turned_in = function(quest_id, rewards)
        if rewards.gold and rewards.gold > 0 then
            level_system:addGold(rewards.gold)
        end

        if rewards.exp and rewards.exp > 0 then
            level_system:addExp(rewards.exp)
        end
    end
end

-- Play BGM for map
function initializers.startBGM(scene, mapPath)
    local level = mapPath:match("level(%d+)")
    if not level then level = "1" end
    level = "level" .. level
    sound:playBGM(level, 1.0, true)
end

-- Setup lighting for current map
function initializers.setupLighting(scene)
    lighting:clearLights()
    local ambient = scene.world.map.properties.ambient or "day"
    lighting:setAmbient(ambient)

    -- Give world access to lighting system
    scene.world.lighting_sys = lighting

    -- Add lights only for dark environments
    if ambient == "day" then
        scene.player.light = nil
        return
    end

    -- Setup player light
    scene.player.light = addEntityLight(scene.player, initializers.LIGHT_CONFIGS.player)

    -- Setup enemy lights
    for _, enemy in ipairs(scene.world.enemies) do
        local x, y = getEntityCenter(enemy)
        enemy.light = addEntityLight(enemy, initializers.LIGHT_CONFIGS.enemy, x, y)
    end

    -- Setup NPC lights
    for _, npc in ipairs(scene.world.npcs) do
        local x, y = getEntityCenter(npc)
        npc.light = addEntityLight(npc, initializers.LIGHT_CONFIGS.npc, x, y)
    end

    -- Setup savepoint lights
    for _, savepoint in ipairs(scene.world.savepoints) do
        savepoint.light = addEntityLight(savepoint, initializers.LIGHT_CONFIGS.savepoint,
                                        savepoint.center_x, savepoint.center_y)
    end
end

-- Exit gameplay scene
function initializers.exit(scene)
    if scene.world then scene.world:destroy() end
    weather:cleanup()
    sound:stopBGM()

    -- Hide virtual gamepad when leaving gameplay
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        virtual_gamepad:hide()
    end
end

-- Resume from pushed scene
function initializers.resume(scene)
    local input = require "engine.core.input"
    input:setSceneContext("gameplay")
end

return initializers

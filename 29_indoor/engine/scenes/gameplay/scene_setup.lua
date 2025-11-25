-- engine/scenes/gameplay/scene_setup.lua
-- Gameplay scene initialization (enter/exit/resume/switchMap)

local scene_setup = {}

-- Module dependencies
local player_module = require "engine.entities.player"
local world = require "engine.systems.world"
local camera = require "vendor.hump.camera"
local camera_sys = require "engine.core.camera"
local display = require "engine.core.display"
local save_sys = require "engine.core.save"
local inventory_class = require "engine.systems.inventory"
local item_class = require "engine.entities.item"
local enemy_class = require "engine.entities.enemy"
local npc_class = require "engine.entities.npc"
local healing_point_class = require "engine.entities.healing_point"
local world_item_class = require "engine.entities.world_item"
local dialogue = require "engine.ui.dialogue"
local sound = require "engine.core.sound"
local util = require "engine.utils.util"
local constants = require "engine.core.constants"
local minimap_class = require "engine.systems.hud.minimap"
local lighting = require "engine.systems.lighting"
local weather = require "engine.systems.weather"
local quest_system = require "engine.core.quest"
local level_system = require "engine.core.level"
local effects = require "engine.systems.effects"
local helpers = require "engine.utils.helpers"

-- Check if on mobile OS
local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")

-- Light configuration constants
local LIGHT_CONFIGS = {
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

-- Helper functions for lighting setup

-- Get entity center position
local function getEntityCenter(entity)
    return entity.x + entity.collider_offset_x,
           entity.y + entity.collider_offset_y
end

-- Add light to entity with given config
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

-- Setup player light
local function setupPlayerLight(player)
    player.light = addEntityLight(player, LIGHT_CONFIGS.player)
end

-- Setup lights for all enemies
local function setupEnemyLights(enemies)
    for _, enemy in ipairs(enemies) do
        local x, y = getEntityCenter(enemy)
        enemy.light = addEntityLight(enemy, LIGHT_CONFIGS.enemy, x, y)
    end
end

-- Setup lights for all NPCs
local function setupNPCLights(npcs)
    for _, npc in ipairs(npcs) do
        local x, y = getEntityCenter(npc)
        npc.light = addEntityLight(npc, LIGHT_CONFIGS.npc, x, y)
    end
end

-- Setup lights for all save points
local function setupSavepointLights(savepoints)
    for _, savepoint in ipairs(savepoints) do
        savepoint.light = addEntityLight(savepoint, LIGHT_CONFIGS.savepoint,
                                        savepoint.center_x, savepoint.center_y)
    end
end

-- Initialize gameplay scene (called from gameplay:enter)
function scene_setup.enter(scene, from_scene, mapPath, spawn_x, spawn_y, save_slot, is_new_game)
    -- Initialize lighting system if not already initialized
    if not lighting.canvas then lighting:init() end

    -- Reset camera effects (shake, slow-motion)
    camera_sys:reset()

    mapPath = mapPath or constants.GAME_START.DEFAULT_MAP
    spawn_x = spawn_x or constants.GAME_START.DEFAULT_SPAWN_X
    spawn_y = spawn_y or constants.GAME_START.DEFAULT_SPAWN_Y
    save_slot = save_slot or 1
    -- Explicit nil check: nil defaults to false, but explicit false/true values are preserved
    if is_new_game == nil then
        is_new_game = false
    end

    scene.current_map_path = mapPath

    -- Store map entry coordinates (for "Restart from Here" functionality)
    scene.map_entry_x = spawn_x
    scene.map_entry_y = spawn_y

    -- Initialize camera
    scene_setup.initCamera(scene)

    -- Load save data first (before creating world)
    local save_data = nil
    if not is_new_game then
        save_data = save_sys:loadGame(save_slot)
    end

    -- Initialize persistence lists (for non-respawning items/enemies)
    scene.picked_items = (save_data and save_data.picked_items) or {}
    scene.killed_enemies = (save_data and save_data.killed_enemies) or {}
    scene.transformed_npcs = (save_data and save_data.transformed_npcs) or {}

    -- Load or reset dialogue choice history
    if save_data and save_data.dialogue_choices then
        dialogue:importChoiceHistory(save_data.dialogue_choices)
    else
        -- New Game: Clear all dialogue history
        dialogue:clearChoiceHistory()
        dialogue:clearAllFlags()
    end

    -- Load or reset quest states
    if save_data and save_data.quest_states then
        quest_system:importStates(save_data.quest_states)
    else
        -- New Game: Reset all quests to initial state
        quest_system:resetAll()
    end

    -- Initialize level system
    scene_setup.initLevelSystem(scene, save_data, is_new_game)

    -- Store quest system reference (for debug display)
    scene.quest_system = quest_system

    -- Create world and player
    scene_setup.createWorld(scene, mapPath)
    scene_setup.createPlayer(scene, spawn_x, spawn_y, save_data)

    -- Initialize systems
    scene_setup.initSystems(scene)
    scene_setup.initInventory(scene, save_data, is_new_game)

    -- Setup UI and scene state
    scene_setup.initUI(scene)
    scene_setup.initSceneState(scene, save_slot)

    -- Setup callbacks
    scene_setup.setupCallbacks(scene)

    -- Play BGM
    scene_setup.startBGM(scene, mapPath)
end

-- Initialize camera
function scene_setup.initCamera(scene)
    local vw, vh = display:GetVirtualDimensions()
    local sw, sh = display:GetScreenDimensions()
    local scale_x = sw / vw
    local scale_y = sh / vh
    local cam_scale = math.min(scale_x, scale_y) * constants.CAMERA.ZOOM_FACTOR

    scene.cam = camera(0, 0, cam_scale, 0, 0)
end

-- Initialize level system
function scene_setup.initLevelSystem(scene, save_data, is_new_game)
    -- Initialize level system with player config
    local level_config = scene.player_config.level_system
    if level_config then
        level_system:init(level_config)
    else
        level_system:init()  -- Use default config
    end

    -- Load level system data from save or reset
    if save_data and save_data.level_data then
        level_system:deserialize(save_data.level_data)
    else
        -- New Game: Reset level to 1
        level_system:reset()
    end
end

-- Create world
function scene_setup.createWorld(scene, mapPath)
    scene.world = world:new(mapPath, {
        enemy = enemy_class,
        npc = npc_class,
        healing_point = healing_point_class,
        world_item = world_item_class,
        loot_tables = scene.loot_tables
    }, scene.picked_items, scene.killed_enemies, scene.transformed_npcs)
end

-- Create player
function scene_setup.createPlayer(scene, spawn_x, spawn_y, save_data)
    scene.player = player_module:new(spawn_x, spawn_y, scene.player_config)

    -- Set player game mode based on world
    scene.player.game_mode = scene.world.game_mode

    -- Apply map-based move mode (walk/run) - for indoor maps etc.
    local map_props = scene.world.map.properties
    if map_props then
        if map_props.move_mode then
            scene.player.default_move = map_props.move_mode  -- "walk" or "run"
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

-- Initialize minimap and weather
function scene_setup.initSystems(scene)
    -- Initialize minimap
    scene.minimap = minimap_class:new()
    scene.minimap:setMap(scene.world)

    -- Initialize weather system
    weather:initialize(scene.world.map)
end

-- Initialize inventory
function scene_setup.initInventory(scene, save_data, is_new_game)
    -- Initialize inventory with item_class injection
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
        -- Give starting items (for both new game and no save data)
        for _, item_config in ipairs(scene.starting_items) do
            scene.inventory:addItem(item_config.type, item_config.quantity)
        end
    end

    -- Inject inventory reference into quest system
    -- (needed for collect quests to check current inventory on accept)
    quest_system.inventory = scene.inventory

    -- Auto-accept tutorial quest for new game
    if is_new_game then
        quest_system:accept("tutorial_talk")
    end
end

-- Initialize UI (dialogue, lighting, input)
function scene_setup.initUI(scene)
    dialogue:initialize(display)

    -- Inject world reference into dialogue (for NPC → Enemy transformations)
    dialogue.world = scene.world

    -- Initialize lighting
    scene_setup.setupLighting(scene)

    -- Show virtual gamepad for mobile gameplay
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        -- Force init if not initialized
        if not virtual_gamepad.enabled then
            virtual_gamepad:init()
        end
        virtual_gamepad:show()
    end

    -- Set game context for input coordinator (for context-based actions)
    local input = require "engine.core.input"
    input:setGameContext({
        player = scene.player,
        world = scene.world
    })

    -- Set scene context for input priority
    input:setSceneContext("gameplay")
end

-- Initialize scene state
function scene_setup.initSceneState(scene, save_slot)
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
    scene.last_selected_quickslot = nil  -- For Y button double-press detection
end

-- Setup system callbacks
function scene_setup.setupCallbacks(scene)
    -- Setup level system callbacks
    level_system.callbacks.on_level_up = function(new_level, stat_bonuses)
        -- Increase player stats on level up
        if stat_bonuses.max_health then
            scene.player.max_health = scene.player.max_health + stat_bonuses.max_health
            -- Also heal player by the bonus amount
            scene.player.health = math.min(scene.player.health + stat_bonuses.max_health, scene.player.max_health)
        end

        if stat_bonuses.speed then
            scene.player.speed = scene.player.speed + stat_bonuses.speed
        end

        -- TODO: Show level up notification (visual effect, sound, UI message)
    end

    -- Setup quest system callbacks for quest completion and rewards
    quest_system.callbacks.on_quest_completed = function(quest_id)
        -- Quest completed (objectives done, ready to turn in)
        -- TODO: Add visual notification (e.g., toast message, sound effect)
    end

    quest_system.callbacks.on_quest_turned_in = function(quest_id, rewards)
        -- Give gold rewards
        if rewards.gold and rewards.gold > 0 then
            level_system:addGold(rewards.gold)
        end

        -- Give exp rewards (may trigger level up)
        if rewards.exp and rewards.exp > 0 then
            level_system:addExp(rewards.exp)
        end

        -- Items are handled in showQuestTurnInDialogue
    end
end

-- Play BGM for map
function scene_setup.startBGM(scene, mapPath)
    local level = mapPath:match("level(%d+)")
    if not level then level = "1" end
    level = "level" .. level
    -- Always rewind BGM on enter (restart/new game)
    sound:playBGM(level, 1.0, true)
end

-- Setup lighting for current map
function scene_setup.setupLighting(scene)
    lighting:clearLights()
    local ambient = scene.world.map.properties.ambient or "day"
    lighting:setAmbient(ambient)

    -- Give world access to lighting system (for entity transformations)
    scene.world.lighting_sys = lighting

    -- Add lights only for dark environments (not day mode)
    if ambient == "day" then
        scene.player.light = nil
        return  -- Early return for day mode
    end

    -- Setup lights for all entities
    setupPlayerLight(scene.player)
    setupEnemyLights(scene.world.enemies)
    setupNPCLights(scene.world.npcs)
    setupSavepointLights(scene.world.savepoints)
end

-- Switch to a new map
function scene_setup.switchMap(scene, new_map_path, spawn_x, spawn_y)
    -- CRITICAL: Sync persistence data from world BEFORE destroying it
    -- (world may have killed enemies, picked items, transformed NPCs that scene doesn't have)
    helpers.syncPersistenceData(scene)

    -- Clean up old colliders BEFORE destroying world
    helpers.destroyColliders(scene.player)

    -- Now destroy world
    if scene.world then scene.world:destroy() end
    weather:cleanup()

    scene.current_map_path = new_map_path

    -- Track location for explore quests
    local location_id = scene_setup.getLocationId(new_map_path)
    if location_id then
        quest_system:onLocationVisited(location_id)
    end

    -- Create world with injected entity classes and persistence data
    scene.world = world:new(new_map_path, {
        enemy = enemy_class,
        npc = npc_class,
        healing_point = healing_point_class,
        world_item = world_item_class,
        loot_tables = scene.loot_tables
    }, scene.picked_items, scene.killed_enemies, scene.transformed_npcs)

    -- Reinitialize weather for new map
    weather:initialize(scene.world.map)

    scene.player.x = spawn_x
    scene.player.y = spawn_y

    -- CRITICAL: Update player game mode BEFORE adding to world
    -- (createPlayerColliders needs correct game_mode to create foot_collider in topdown)
    scene.player.game_mode = scene.world.game_mode

    -- Apply map-based move mode (walk/run) - reset to config default if not specified
    local map_props = scene.world.map.properties
    local config_default = scene.player_config.animations and scene.player_config.animations.default_move or "walk"
    scene.player.default_move = (map_props and map_props.move_mode) or config_default

    scene.world:addEntity(scene.player)

    -- Update minimap for new map
    if scene.minimap then
        scene.minimap:setMap(scene.world)
    end

    -- Update dialogue world reference (for NPC transformations)
    dialogue.world = scene.world

    -- Update lighting for new map
    scene_setup.setupLighting(scene)

    -- Handle BGM based on map properties
    local map_bgm = scene.world.map.properties and scene.world.map.properties.bgm

    if map_bgm then
        -- Map has custom BGM property, use it
        sound:playBGM(map_bgm, 1.0, false)  -- rewind=false for smooth transition
    else
        -- No custom BGM, use level-based BGM (default behavior)
        local level = new_map_path:match("level(%d+)")
        if not level then level = "1" end
        level = "level" .. level
        sound:playBGM(level, 1.0, false)  -- rewind=false to continue if same BGM
    end

    scene.transition_cooldown = 0.5

    scene.cam:lookAt(scene.player.x, scene.player.y)

    local mapWidth = scene.world.map.width * scene.world.map.tilewidth
    local mapHeight = scene.world.map.height * scene.world.map.tileheight

    local w, h = util:Get16by9Size(love.graphics.getWidth(), love.graphics.getHeight())
    scene.cam:lockBounds(mapWidth, mapHeight, w, h)

    scene.fade_alpha = 1.0
    scene.is_fading = true
end

-- Helper: Get location ID from map path
function scene_setup.getLocationId(map_path)
    -- Extract location ID from map path
    -- Example: "assets/maps/level1/area2.lua" -> "level1_area2"
    local level = map_path:match("level(%d+)")
    local area = map_path:match("area(%d+)")

    if level and area then
        return "level" .. level .. "_area" .. area
    end

    return nil
end

-- Exit gameplay scene
function scene_setup.exit(scene)
    if scene.world then scene.world:destroy() end
    weather:cleanup()
    sound:stopBGM()

    -- Hide virtual gamepad when leaving gameplay
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        virtual_gamepad:hide()
    end
end

-- Resume from pushed scene (e.g., inventory)
function scene_setup.resume(scene)
    local input = require "engine.core.input"
    input:setSceneContext("gameplay")
end

return scene_setup

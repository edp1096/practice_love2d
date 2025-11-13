-- systems/world/init.lua
-- Main coordinator for the world system

local sti = require "vendor.sti"
local windfield = require "vendor.windfield"
local effects = require "engine.systems.effects"
local game_mode = require "engine.systems.game_mode"
local collision = require "engine.systems.collision"

local loaders = require "engine.systems.world.loaders"
local entities = require "engine.systems.world.entities"
local rendering = require "engine.systems.world.rendering"

local world = {}
world.__index = world

-- Injected entity classes (set from game code)
world.enemy_class = nil
world.npc_class = nil
world.healing_point_class = nil
world.world_item_class = nil
world.loot_tables = nil

function world:new(map_path, entity_classes)
    local instance = setmetatable({}, world)

    -- Store injected entity classes (fallback to class-level if not provided)
    entity_classes = entity_classes or {}
    instance.enemy_class = entity_classes.enemy or self.enemy_class
    instance.npc_class = entity_classes.npc or self.npc_class
    instance.healing_point_class = entity_classes.healing_point or self.healing_point_class
    instance.world_item_class = entity_classes.world_item or self.world_item_class
    instance.loot_tables = entity_classes.loot_tables or self.loot_tables

    local map_info = love.filesystem.getInfo(map_path)
    if not map_info then
        error("Map file not found: " .. map_path)
    end

    instance.map = sti(map_path)

    -- Read game mode from map properties
    local mode = "topdown" -- default
    if instance.map.properties and instance.map.properties.game_mode then
        mode = instance.map.properties.game_mode
    end

    -- Set game mode
    game_mode:set(mode)
    instance.game_mode = mode

    -- Get gravity based on game mode
    local gx, gy = game_mode:getGravity()
    instance.physicsWorld = windfield.newWorld(gx, gy, true)

    -- Setup collision classes and ignore rules
    collision.setupCollisionClasses(instance.physicsWorld, mode)

    -- Set debug draw colors for collision classes
    instance.physicsWorld:setQueryDebugDrawing(true)
    -- PlayerFoot: Deep pink
    if instance.physicsWorld.collision_classes.PlayerFoot then
        instance.physicsWorld.collision_classes.PlayerFoot.draw_color = {1.0, 0.08, 0.58}  -- Deep pink
    end
    -- EnemyFoot: Orange
    if instance.physicsWorld.collision_classes.EnemyFoot then
        instance.physicsWorld.collision_classes.EnemyFoot.draw_color = {1.0, 0.5, 0.0}  -- Orange
    end

    instance.walls = {}
    loaders.loadWalls(instance)

    -- Load Trees layer tiles for Y-sorting (topdown mode only)
    if instance.game_mode == "topdown" then
        loaders.loadTreeTiles(instance)
    end

    loaders.loadTransitions(instance)

    instance.enemies = {}
    loaders.loadEnemies(instance)

    instance.npcs = {}
    loaders.loadNPCs(instance)

    instance.savepoints = {}
    loaders.loadSavePoints(instance)

    instance.healing_points = {}
    loaders.loadHealingPoints(instance)

    instance.death_zones = {}
    loaders.loadDeathZones(instance)

    instance.damage_zones = {}
    loaders.loadDamageZones(instance)

    -- World items (dropped items)
    instance.world_items = {}
    loaders.loadWorldItems(instance)

    return instance
end

function world:update(dt)
    self.physicsWorld:update(dt)
    self.map:update(dt)
    effects:update(dt)

    -- Update world items
    entities.updateWorldItems(self, dt)
end

function world:destroy()
    if self.physicsWorld then self.physicsWorld:destroy() end
end

function world:checkTransition(player_x, player_y, player_w, player_h)
    for _, transition in ipairs(self.transitions) do
        if player_x < transition.x + transition.width and
            player_x + player_w > transition.x and
            player_y < transition.y + transition.height and
            player_y + player_h > transition.y then
            return transition
        end
    end

    return nil
end

-- Delegate loader functions
world.loadWalls = loaders.loadWalls
world.loadTransitions = loaders.loadTransitions
world.loadSavePoints = loaders.loadSavePoints
world.loadEnemies = loaders.loadEnemies
world.loadNPCs = loaders.loadNPCs
world.loadHealingPoints = loaders.loadHealingPoints
world.loadDeathZones = loaders.loadDeathZones
world.loadDamageZones = loaders.loadDamageZones

-- Delegate entity management functions
world.addEntity = entities.addEntity
world.addEnemy = entities.addEnemy
world.moveEntity = entities.moveEntity
world.updateEnemies = entities.updateEnemies
world.updateNPCs = entities.updateNPCs
world.updateHealingPoints = entities.updateHealingPoints
world.updateSavePoints = entities.updateSavePoints
world.checkLineOfSight = entities.checkLineOfSight
world.checkWeaponCollisions = entities.checkWeaponCollisions
world.applyWeaponHit = entities.applyWeaponHit
world.getInteractableNPC = entities.getInteractableNPC
world.getInteractableSavePoint = entities.getInteractableSavePoint
world.addWorldItem = entities.addWorldItem
world.updateWorldItems = entities.updateWorldItems
world.getInteractableWorldItem = entities.getInteractableWorldItem
world.removeWorldItem = entities.removeWorldItem

-- Delegate rendering functions
world.draw = rendering.draw
world.drawLayer = rendering.drawLayer
world.drawEntitiesYSorted = rendering.drawEntitiesYSorted
world.drawSavePoints = rendering.drawSavePoints
world.drawHealingPoints = rendering.drawHealingPoints
world.drawHealingPointsDebug = rendering.drawHealingPointsDebug
world.drawWorldItems = rendering.drawWorldItems
world.drawDebug = rendering.drawDebug

return world

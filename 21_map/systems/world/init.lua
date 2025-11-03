-- systems/world/init.lua
-- Main coordinator for the world system

local sti = require "vendor.sti"
local windfield = require "vendor.windfield"
local effects = require "systems.effects"
local game_mode = require "systems.game_mode"

local loaders = require "systems.world.loaders"
local entities = require "systems.world.entities"
local rendering = require "systems.world.rendering"

local world = {}
world.__index = world

function world:new(map_path)
    local instance = setmetatable({}, world)

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

    instance.physicsWorld:addCollisionClass("Player")
    instance.physicsWorld:addCollisionClass("PlayerDodging")
    instance.physicsWorld:addCollisionClass("Wall")
    instance.physicsWorld:addCollisionClass("Portals")
    instance.physicsWorld:addCollisionClass("Enemy")
    instance.physicsWorld:addCollisionClass("Item")

    instance.physicsWorld.collision_classes.PlayerDodging.ignores = { "Enemy" }

    instance.physicsWorld:collisionClassesSet()

    instance.walls = {}
    loaders.loadWalls(instance)

    loaders.loadTransitions(instance)

    instance.enemies = {}
    loaders.loadEnemies(instance)

    instance.npcs = {}
    loaders.loadNPCs(instance)

    instance.savepoints = {}
    loaders.loadSavePoints(instance)

    instance.healing_points = {}
    loaders.loadHealingPoints(instance)

    return instance
end

function world:update(dt)
    self.physicsWorld:update(dt)
    self.map:update(dt)
    effects:update(dt)
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

-- Delegate rendering functions
world.draw = rendering.draw
world.drawLayer = rendering.drawLayer
world.drawEntitiesYSorted = rendering.drawEntitiesYSorted
world.drawSavePoints = rendering.drawSavePoints
world.drawHealingPoints = rendering.drawHealingPoints
world.drawHealingPointsDebug = rendering.drawHealingPointsDebug
world.drawDebug = rendering.drawDebug

return world

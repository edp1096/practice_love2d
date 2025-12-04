-- engine/systems/collision/init.lua
-- Main collision system API - delegates to specialized modules

local classes = require "engine.systems.collision.classes"
local player_collision = require "engine.systems.collision.player"
local enemy_collision = require "engine.systems.collision.enemy"
local npc_collision = require "engine.systems.collision.npc"
local prop_collision = require "engine.systems.collision.prop"
local vehicle_collision = require "engine.systems.collision.vehicle"
local walls = require "engine.systems.collision.walls"
local zones = require "engine.systems.collision.zones"

local collision = {}

-- Setup collision classes and ignore rules for physics world
function collision.setupCollisionClasses(physicsWorld, game_mode)
    classes.setup(physicsWorld, game_mode)
end

-- Create colliders for player entity
function collision.createPlayerColliders(player, physicsWorld)
    player_collision.create(player, physicsWorld)
end

-- Create colliders for wall object (returns main wall collider and optional bottom collider)
function collision.createWallColliders(obj, physicsWorld, game_mode)
    return walls.create(obj, physicsWorld, game_mode)
end

-- Create collider for enemy entity
function collision.createEnemyCollider(enemy, physicsWorld, game_mode)
    enemy_collision.create(enemy, physicsWorld, game_mode)
end

-- Create collider for NPC entity
function collision.createNPCCollider(npc, physicsWorld, game_mode)
    npc_collision.create(npc, physicsWorld, game_mode)
end

-- Create collider for Prop entity
function collision.createPropCollider(prop, physicsWorld, game_mode)
    prop_collision.create(prop, physicsWorld, game_mode)
end

-- Create collider for Vehicle entity
function collision.createVehicleCollider(vehicle, physicsWorld, game_mode)
    vehicle_collision.create(vehicle, physicsWorld, game_mode)
end

-- Create collider for death zone (returns collider or nil)
function collision.createDeathZoneCollider(obj, physicsWorld)
    return zones.createDeathZone(obj, physicsWorld)
end

-- Create collider for damage zone (returns zone data with collider and properties, or nil)
function collision.createDamageZoneCollider(obj, physicsWorld)
    return zones.createDamageZone(obj, physicsWorld)
end

return collision

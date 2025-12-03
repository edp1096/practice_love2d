-- engine/systems/collision/helpers.lua
-- Common helper functions for collider creation

local constants = require "engine.core.constants"

local helpers = {}

-- Create a BSG rectangle collider with common settings
-- Returns the created collider
function helpers.createBSGCollider(physicsWorld, x, y, w, h, radius, collisionClass, entity)
    local collider = physicsWorld:newBSGRectangleCollider(x, y, w, h, radius)
    collider:setFixedRotation(true)
    collider:setCollisionClass(collisionClass)
    if entity then
        collider:setObject(entity)
    end
    return collider
end

-- Create a rectangle collider with common settings
-- Returns the created collider
function helpers.createRectCollider(physicsWorld, x, y, w, h, collisionClass, entity)
    local collider = physicsWorld:newRectangleCollider(x, y, w, h)
    collider:setFixedRotation(true)
    collider:setCollisionClass(collisionClass)
    if entity then
        collider:setObject(entity)
    end
    return collider
end

-- Calculate foot collider dimensions for an entity type
-- Returns: height, y_offset (relative to main collider center)
function helpers.getFootDimensions(collider_height, entity_type)
    local offsets = constants.COLLIDER_OFFSETS

    if entity_type == "player" then
        return collider_height * offsets.PLAYER_FOOT_HEIGHT,
               collider_height * offsets.PLAYER_FOOT_POSITION
    elseif entity_type == "humanoid" then
        return collider_height * offsets.HUMANOID_FOOT_HEIGHT,
               collider_height * offsets.HUMANOID_FOOT_POSITION
    elseif entity_type == "slime" then
        return collider_height * offsets.SLIME_FOOT_HEIGHT,
               collider_height * offsets.SLIME_FOOT_POSITION
    elseif entity_type == "npc" then
        return collider_height * offsets.NPC_FOOT_HEIGHT,
               collider_height * offsets.NPC_FOOT_POSITION
    else
        -- Default to player-like proportions
        return collider_height * offsets.PLAYER_FOOT_HEIGHT,
               collider_height * offsets.PLAYER_FOOT_POSITION
    end
end

-- Create a foot collider for topdown mode
-- entity_type: "player", "humanoid", "slime", "npc"
-- Returns the created foot collider
function helpers.createFootCollider(physicsWorld, x, y, width, height, entity_type, collisionClass, entity)
    local foot_height, y_offset = helpers.getFootDimensions(height, entity_type)

    local collider = physicsWorld:newBSGRectangleCollider(
        x,
        y + y_offset,
        width,
        foot_height,
        5  -- Standard smaller corner radius for foot colliders
    )
    collider:setFixedRotation(true)
    collider:setCollisionClass(collisionClass)
    collider:setFriction(0.0)
    if entity then
        collider:setObject(entity)
    end
    return collider
end

return helpers

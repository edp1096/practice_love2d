-- engine/systems/collision/npc.lua
-- NPC collider creation

local constants = require "engine.core.constants"

local npc_collision = {}

-- Create collider for NPC entity
function npc_collision.create(npc, physicsWorld, game_mode)
    local bounds = npc:getColliderBounds()
    npc.collider = physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    npc.collider:setFixedRotation(true)
    npc.collider:setType("static")
    npc.collider:setCollisionClass(constants.COLLISION_CLASSES.NPC)
    npc.collider:setObject(npc)

    -- Platformer: Make NPC a sensor (no physical collision, only detection)
    -- Prevents player from standing on NPC like a platform
    if game_mode == "platformer" then
        npc.collider:setSensor(true)
    end

    -- Update NPC position to match collider
    npc.x = npc.collider:getX() - npc.collider_offset_x
    npc.y = npc.collider:getY() - npc.collider_offset_y
end

return npc_collision

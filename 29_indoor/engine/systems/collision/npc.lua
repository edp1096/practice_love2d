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

    -- NOTE: Do NOT update npc.x/y here
    -- The collider is created at getColliderBounds() position (which is npc.x + offset)
    -- npc.x/y should remain unchanged as the sprite position
end

return npc_collision

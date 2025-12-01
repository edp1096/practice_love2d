-- engine/systems/collision/npc.lua
-- NPC collider creation

local constants = require "engine.core.constants"

local npc_collision = {}

-- Create colliders for NPC entity
function npc_collision.create(npc, physicsWorld, game_mode)
    local bounds = npc:getColliderBounds()

    -- Main collider (interaction detection, combat in platformer)
    -- bounds.x/y are center point, need to pass top-left corner
    npc.collider = physicsWorld:newBSGRectangleCollider(
        bounds.left, bounds.top,
        bounds.width, bounds.height,
        8
    )
    npc.collider:setFixedRotation(true)
    npc.collider:setType("static")
    npc.collider:setCollisionClass(constants.COLLISION_CLASSES.NPC)
    npc.collider:setObject(npc)

    -- Topdown mode: Add foot collider (bottom 25% of main collider)
    if game_mode == "topdown" then
        local foot_height = bounds.height * 0.25
        local foot_top = bounds.top + bounds.height * 0.75  -- Start at 75% down (bottom 25%)

        npc.foot_collider = physicsWorld:newBSGRectangleCollider(
            bounds.left,
            foot_top,
            bounds.width,
            foot_height,
            4  -- Smaller corner radius
        )
        npc.foot_collider:setFixedRotation(true)
        npc.foot_collider:setType("static")
        npc.foot_collider:setCollisionClass(constants.COLLISION_CLASSES.NPC_FOOT)
        npc.foot_collider:setObject(npc)
    end

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

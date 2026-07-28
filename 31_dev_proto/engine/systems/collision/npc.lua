-- engine/systems/collision/npc.lua
-- NPC collider creation

local constants = require "engine.core.constants"
local helpers = require "engine.systems.collision.helpers"

local npc_collision = {}

-- Create colliders for NPC entity
function npc_collision.create(npc, physicsWorld, game_mode)
    local bounds = npc:getColliderBounds()

    -- Main collider (interaction detection, combat in platformer)
    -- bounds.x/y are center point, need to pass top-left corner
    npc.collider = helpers.createBSGCollider(
        physicsWorld,
        bounds.left, bounds.top,
        bounds.width, bounds.height,
        8, constants.COLLISION_CLASSES.NPC, npc
    )
    npc.collider:setType("static")

    -- Topdown mode: Add foot collider (bottom 25% of main collider)
    if game_mode == "topdown" then
        local offsets = constants.COLLIDER_OFFSETS
        local foot_height = bounds.height * offsets.NPC_FOOT_HEIGHT
        local foot_top = bounds.top + bounds.height * offsets.NPC_FOOT_POSITION

        npc.foot_collider = helpers.createBSGCollider(
            physicsWorld,
            bounds.left, foot_top,
            bounds.width, foot_height,
            4, constants.COLLISION_CLASSES.NPC_FOOT, npc
        )
        npc.foot_collider:setType("static")
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

-- engine/systems/collision/enemy.lua
-- Enemy collider creation

local constants = require "engine.core.constants"
local helpers = require "engine.systems.collision.helpers"

local enemy_collision = {}

-- Create collider for enemy entity
function enemy_collision.create(enemy, physicsWorld, game_mode)
    if enemy.collider then
        return  -- Already has colliders
    end

    -- Store game mode for later use
    enemy.game_mode = game_mode

    local bounds = enemy:getColliderBounds()

    -- Main collider (combat, physics)
    enemy.collider = helpers.createBSGCollider(
        physicsWorld,
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8, constants.COLLISION_CLASSES.ENEMY, enemy
    )

    -- Topdown mode: Add foot collider based on enemy type
    if game_mode == "topdown" then
        local entity_type = enemy.is_humanoid and "humanoid" or "slime"
        enemy.foot_collider = helpers.createFootCollider(
            physicsWorld,
            bounds.x, bounds.y,
            enemy.collider_width, enemy.collider_height,
            entity_type, constants.COLLISION_CLASSES.ENEMY_FOOT, enemy
        )
    end

    -- Platformer mode: remove air resistance for faster falling
    if game_mode == "platformer" then
        enemy.collider:setLinearDamping(0)
        enemy.collider:setGravityScale(1)

        local body = enemy.collider.body
        if body then
            body:setLinearDamping(0)
        end
    end
end

return enemy_collision

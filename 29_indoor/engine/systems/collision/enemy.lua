-- engine/systems/collision/enemy.lua
-- Enemy collider creation

local constants = require "engine.core.constants"

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
    enemy.collider = physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    enemy.collider:setFixedRotation(true)
    enemy.collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY)
    enemy.collider:setObject(enemy)

    -- Topdown mode: Add foot collider based on enemy type
    if game_mode == "topdown" then
        if enemy.is_humanoid then
            -- Humanoid enemies: foot collider like player (12.5% height at bottom)
            local bottom_height = enemy.collider_height * 0.125  -- Bottom 12.5%
            local bottom_y_offset = enemy.collider_height * 0.4375  -- Position at 87.5% down

            enemy.foot_collider = physicsWorld:newBSGRectangleCollider(
                bounds.x,
                bounds.y + bottom_y_offset,
                enemy.collider_width,
                bottom_height,
                5  -- Smaller corner radius
            )
            enemy.foot_collider:setFixedRotation(true)
            enemy.foot_collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY_FOOT)
            enemy.foot_collider:setFriction(0.0)
            enemy.foot_collider:setObject(enemy)  -- Link back to enemy
        else
            -- Slime enemies: bottom 60% collision (no visible feet)
            local bottom_height = enemy.collider_height * 0.6  -- Bottom 60%
            local bottom_y_offset = enemy.collider_height * 0.2  -- Position at 40% down

            enemy.foot_collider = physicsWorld:newBSGRectangleCollider(
                bounds.x,
                bounds.y + bottom_y_offset,
                enemy.collider_width,
                bottom_height,
                5
            )
            enemy.foot_collider:setFixedRotation(true)
            enemy.foot_collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY_FOOT)
            enemy.foot_collider:setFriction(0.0)
            enemy.foot_collider:setObject(enemy)
        end
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

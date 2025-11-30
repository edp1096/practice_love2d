-- engine/systems/collision/player.lua
-- Player collider creation

local constants = require "engine.core.constants"

local player_collision = {}

-- Create colliders for player entity
function player_collision.create(player, physicsWorld)
    if player.collider then
        return  -- Already has colliders
    end

    -- Main collider (combat, platformer physics)
    player.collider = physicsWorld:newBSGRectangleCollider(
        player.x, player.y,
        player.collider_width, player.collider_height,
        10
    )
    player.collider:setFixedRotation(true)
    player.collider:setCollisionClass(constants.COLLISION_CLASSES.PLAYER)
    player.collider:setFriction(0.0)  -- No friction for better platformer feel

    -- Topdown mode: Add foot collider (bottom only)
    if player.game_mode == "topdown" then
        local bottom_height = player.collider_height * 0.2465
        local bottom_y_offset = player.collider_height * 0.40625  -- Position at 81.25% down

        player.foot_collider = physicsWorld:newBSGRectangleCollider(
            player.x,
            player.y + bottom_y_offset,
            player.collider_width,
            bottom_height,
            5  -- Smaller corner radius
        )
        player.foot_collider:setFixedRotation(true)
        player.foot_collider:setCollisionClass(constants.COLLISION_CLASSES.PLAYER_FOOT)
        player.foot_collider:setFriction(0.0)
        player.foot_collider:setObject(player)  -- Link back to player
    end

    -- Platformer grounded detection using PreSolve
    player.collider:setPreSolve(function(collider_1, collider_2, contact)
        if player.game_mode == "platformer" then
            local nx, ny = contact:getNormal()
            local _, vy = player.collider:getLinearVelocity()

            -- Check if normal is mostly vertical (player on top or bottom of object)
            if math.abs(ny) > 0.7 then
                -- Player is on ground if normal points up or player is falling/nearly stationary
                -- Use threshold of -10 to prevent flickering when standing still
                -- (Box2D can produce small negative velocities due to physics settling)
                if ny < 0 or (ny > 0 and vy >= -10) then
                    player.is_grounded = true
                    player.can_jump = true
                    player.is_jumping = false

                    -- Store contact surface Y position for shadow rendering
                    local points = {contact:getPositions()}
                    if #points >= 2 then
                        player.contact_surface_y = points[2]
                    end
                end
            end
        end
    end)
end

return player_collision

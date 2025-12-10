-- engine/systems/collision/vehicle.lua
-- Vehicle collider creation

local constants = require "engine.core.constants"
local helpers = require "engine.systems.collision.helpers"

local vehicle_collision = {}

-- Create colliders for Vehicle entity
function vehicle_collision.create(vehicle, physicsWorld, game_mode)
    local x, y = vehicle.x, vehicle.y
    local w, h = vehicle.collider_width, vehicle.collider_height

    -- Convert center to top-left (newBSGRectangleCollider expects top-left)
    local left = x - w / 2
    local top = y - h / 2

    -- Main collider (interaction detection)
    vehicle.collider = helpers.createBSGCollider(
        physicsWorld,
        left, top,
        w, h,
        8, constants.COLLISION_CLASSES.VEHICLE, vehicle
    )
    vehicle.collider:setType("static")

    -- Topdown mode: Add foot collider (bottom 30% of main collider)
    if game_mode == "topdown" then
        local offsets = constants.COLLIDER_OFFSETS
        local foot_height = h * offsets.VEHICLE_FOOT_HEIGHT
        local foot_top = top + h - foot_height  -- Bottom edge of main collider

        vehicle.foot_collider = helpers.createBSGCollider(
            physicsWorld,
            left, foot_top,
            w, foot_height,
            4, constants.COLLISION_CLASSES.VEHICLE_FOOT, vehicle
        )
        vehicle.foot_collider:setType("static")
    end

    -- Platformer mode: Set collider as sensor (interaction only, no physics blocking)
    -- Vehicle shouldn't block player/enemy movement in platformer
    if game_mode == "platformer" then
        vehicle.collider:setSensor(true)
    end
end

return vehicle_collision

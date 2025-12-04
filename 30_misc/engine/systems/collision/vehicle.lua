-- engine/systems/collision/vehicle.lua
-- Vehicle collider creation

local constants = require "engine.core.constants"
local helpers = require "engine.systems.collision.helpers"

local vehicle_collision = {}

-- Create colliders for Vehicle entity
function vehicle_collision.create(vehicle, physicsWorld, game_mode)
    local x, y = vehicle.x, vehicle.y
    local w, h = vehicle.collider_width, vehicle.collider_height

    -- Calculate bounds (center-based)
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

    -- Topdown mode: Add foot collider
    if game_mode == "topdown" then
        local offsets = constants.COLLIDER_OFFSETS
        local foot_height = h * offsets.VEHICLE_FOOT_HEIGHT
        local foot_top = top + h * (1 - offsets.VEHICLE_FOOT_HEIGHT)

        vehicle.foot_collider = helpers.createBSGCollider(
            physicsWorld,
            left, foot_top,
            w, foot_height,
            4, constants.COLLISION_CLASSES.VEHICLE_FOOT, vehicle
        )
        vehicle.foot_collider:setType("static")
    end

    -- Platformer: Make vehicle a sensor
    if game_mode == "platformer" then
        vehicle.collider:setSensor(true)
    end
end

return vehicle_collision

-- engine/systems/collision/walls.lua
-- Wall collider creation using shape handlers

local constants = require "engine.core.constants"
local rectangle = require "engine.systems.collision.shapes.rectangle"
local polygon = require "engine.systems.collision.shapes.polygon"
local polyline = require "engine.systems.collision.shapes.polyline"
local ellipse = require "engine.systems.collision.shapes.ellipse"

local walls = {}

-- Shape handlers registry
local shapeHandlers = {
    rectangle = rectangle.create,
    polygon = polygon.create,
    polyline = polyline.create,
    ellipse = ellipse.create
}

-- Create colliders for wall object (returns main wall collider and optional bottom collider)
function walls.create(obj, physicsWorld, game_mode)
    local colliders = {}

    -- Get shape handler
    local handler = shapeHandlers[obj.shape]
    if not handler then
        print("Warning: Unknown shape type '" .. tostring(obj.shape) .. "' in Walls layer")
        return colliders
    end

    -- Create main wall collider
    local success, wall = handler(physicsWorld, obj)
    if not success or not wall then
        return colliders
    end

    wall:setType("static")
    wall:setCollisionClass(constants.COLLISION_CLASSES.WALL)
    wall:setFriction(0.0)
    table.insert(colliders, wall)

    -- Topdown mode: Create base collider for wall surface
    if game_mode == "topdown" and obj.shape == "rectangle" then
        local bottom_height = math.max(8, obj.height * 0.15)  -- Bottom 15%, min 8px
        local base_collider = physicsWorld:newRectangleCollider(
            obj.x,
            obj.y + obj.height - bottom_height,  -- Position at bottom
            obj.width,
            bottom_height
        )
        base_collider:setType("static")
        base_collider:setCollisionClass(constants.COLLISION_CLASSES.WALL_BASE)
        base_collider:setFriction(0.0)
        table.insert(colliders, base_collider)
    end

    return colliders
end

return walls

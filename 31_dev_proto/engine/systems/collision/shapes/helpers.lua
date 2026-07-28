-- engine/systems/collision/shapes/helpers.lua
-- Shared utilities for collision shape creation

local constants = require "engine.core.constants"

local helpers = {}

-- Compute bounding box from flat vertices array
-- @param vertices: flat array {x1, y1, x2, y2, ...}
-- @return min_x, min_y, max_x, max_y
function helpers.computeBoundingBox(vertices)
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge
    for i = 1, #vertices, 2 do
        min_x = math.min(min_x, vertices[i])
        min_y = math.min(min_y, vertices[i + 1])
        max_x = math.max(max_x, vertices[i])
        max_y = math.max(max_y, vertices[i + 1])
    end
    return min_x, min_y, max_x, max_y
end

-- Create a static wall rectangle collider
-- @param world: physics world
-- @param x, y, w, h: rectangle bounds
-- @return collider
function helpers.createRectangleWall(world, x, y, w, h)
    local collider = world:newRectangleCollider(x, y, w, h)
    collider:setType("static")
    collider:setCollisionClass(constants.COLLISION_CLASSES.WALL)
    collider:setFriction(0.0)
    return collider
end

-- Create colliders from triangulated vertices
-- @param world: physics world
-- @param triangles: result from love.math.triangulate
-- @return array of colliders
function helpers.createTriangulatedColliders(world, triangles)
    local colliders = {}
    for _, triangle in ipairs(triangles) do
        local success, collider = pcall(world.newPolygonCollider, world, triangle, {
            body_type = 'static',
            collision_class = 'Wall'
        })
        if success and collider then
            collider:setType("static")
            collider:setCollisionClass(constants.COLLISION_CLASSES.WALL)
            collider:setFriction(0.0)
            table.insert(colliders, collider)
        end
    end
    return colliders
end

-- Triangulate vertices and create colliders, with bounding box fallback
-- @param world: physics world
-- @param vertices: flat vertices array
-- @param offset_x, offset_y: optional offset for fallback rectangle
-- @return success, collider (first one, others already in physics world)
function helpers.triangulateAndCreate(world, vertices, offset_x, offset_y)
    offset_x = offset_x or 0
    offset_y = offset_y or 0

    local success, triangles = pcall(love.math.triangulate, vertices)
    if not success or not triangles then
        print("Triangulation failed - using bounding box fallback")
        local min_x, min_y, max_x, max_y = helpers.computeBoundingBox(vertices)
        local collider = helpers.createRectangleWall(
            world,
            offset_x + min_x,
            offset_y + min_y,
            max_x - min_x,
            max_y - min_y
        )
        return true, collider
    end

    local colliders = helpers.createTriangulatedColliders(world, triangles)
    if #colliders > 0 then
        return true, colliders[1]
    end
    return false, nil
end

return helpers

-- engine/systems/collision/shapes/polygon.lua
-- Polygon shape handler with concave support via triangulation

local helpers = require "engine.systems.collision.shapes.helpers"

local polygon = {}

function polygon.create(world, object)
    if not object.polygon then return false, nil end

    local vertices = {}
    for _, point in ipairs(object.polygon) do
        table.insert(vertices, point.x)
        table.insert(vertices, point.y)
    end

    -- Skip triangulation for triangles (already convex)
    if #object.polygon == 3 then
        return pcall(world.newPolygonCollider, world, vertices, {
            body_type = 'static',
            collision_class = 'Wall'
        })
    end

    -- For 4+ points, triangulate to ensure proper concave handling
    return helpers.triangulateAndCreate(world, vertices, object.x, object.y)
end

return polygon

-- engine/systems/collision/shapes/polyline.lua
-- Polyline shape handler with closed polyline triangulation (same as polygon)

local helpers = require "engine.systems.collision.shapes.helpers"

local polyline = {}

function polyline.create(world, object)
    if not object.polyline then return false, nil end

    local vertices = {}
    for _, point in ipairs(object.polyline) do
        table.insert(vertices, object.x + point.x)
        table.insert(vertices, object.y + point.y)
    end

    -- Check if polyline is closed (first and last points match OR is_closed property)
    local is_closed = false
    if #object.polyline >= 3 then
        local first = object.polyline[1]
        local last = object.polyline[#object.polyline]
        is_closed = (first.x == last.x and first.y == last.y)
    end

    -- Check for explicit is_closed property from Tiled
    if object.properties and object.properties.is_closed then
        is_closed = object.properties.is_closed
    end

    -- If closed polyline, treat it like polygon (with triangulation for concave support)
    if is_closed and #object.polyline >= 4 then
        -- Build polygon vertices (remove duplicate last point)
        local polygon_vertices = {}
        for i = 1, #object.polyline - 1 do
            local point = object.polyline[i]
            table.insert(polygon_vertices, object.x + point.x)
            table.insert(polygon_vertices, object.y + point.y)
        end

        local point_count = #object.polyline - 1

        -- Skip triangulation for triangles (already convex)
        if point_count == 3 then
            return pcall(world.newPolygonCollider, world, polygon_vertices, {
                body_type = 'static',
                collision_class = 'Wall'
            })
        end

        -- For 4+ points, triangulate (offset is 0 since vertices already include object.x/y)
        return helpers.triangulateAndCreate(world, polygon_vertices, 0, 0)
    end

    -- Use chain collider only for truly open lines
    return pcall(world.newChainCollider, world, vertices, is_closed, {
        body_type = 'static',
        collision_class = 'Wall'
    })
end

return polyline

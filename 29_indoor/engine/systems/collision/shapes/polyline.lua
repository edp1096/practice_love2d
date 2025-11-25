-- engine/systems/collision/shapes/polyline.lua
-- Polyline shape handler with closed polyline triangulation (same as polygon)

local constants = require "engine.core.constants"

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

    -- If closed polyline, treat it EXACTLY like polygon (with triangulation for concave support)
    if is_closed and #object.polyline >= 4 then
        -- Remove duplicate last point for polygon
        local polygon_vertices = {}
        for i = 1, #object.polyline - 1 do
            local point = object.polyline[i]
            table.insert(polygon_vertices, object.x + point.x)
            table.insert(polygon_vertices, object.y + point.y)
        end

        local point_count = #object.polyline - 1  -- -1 because we removed duplicate last point

        -- Skip triangulation for triangles (already convex)
        if point_count == 3 then
            return pcall(world.newPolygonCollider, world, polygon_vertices, {
                body_type = 'static',
                collision_class = 'Wall'
            })
        end

        -- For 4+ points, always triangulate to ensure proper concave handling (same as polygon)
        print("Triangulating closed polyline (" .. point_count .. " points) at x=" .. object.x .. ", y=" .. object.y)

        local triangles_success, triangles = pcall(love.math.triangulate, polygon_vertices)
        if not triangles_success or not triangles then
            print("Triangulation failed - using bounding box fallback")
            -- Fallback to rectangle using bounding box
            local min_x, min_y = math.huge, math.huge
            local max_x, max_y = -math.huge, -math.huge
            for i = 1, #polygon_vertices, 2 do
                min_x = math.min(min_x, polygon_vertices[i])
                min_y = math.min(min_y, polygon_vertices[i + 1])
                max_x = math.max(max_x, polygon_vertices[i])
                max_y = math.max(max_y, polygon_vertices[i + 1])
            end
            local rect_wall = world:newRectangleCollider(min_x, min_y, max_x - min_x, max_y - min_y)
            rect_wall:setType("static")
            rect_wall:setCollisionClass(constants.COLLISION_CLASSES.WALL)
            rect_wall:setFriction(0.0)
            return true, rect_wall
        end

        -- Create collider for each triangle
        local colliders = {}
        for _, triangle in ipairs(triangles) do
            local tri_success, tri_wall = pcall(world.newPolygonCollider, world, triangle, {
                body_type = 'static',
                collision_class = 'Wall'
            })

            if tri_success and tri_wall then
                tri_wall:setType("static")
                tri_wall:setCollisionClass(constants.COLLISION_CLASSES.WALL)
                tri_wall:setFriction(0.0)
                table.insert(colliders, tri_wall)
            end
        end

        -- Return first collider (others are already in physics world)
        if #colliders > 0 then
            return true, colliders[1]
        else
            return false, nil
        end
    end

    -- Use chain collider only for truly open lines
    return pcall(world.newChainCollider, world, vertices, is_closed, {
        body_type = 'static',
        collision_class = 'Wall'
    })
end

return polyline

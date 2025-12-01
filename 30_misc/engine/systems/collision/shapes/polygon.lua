-- engine/systems/collision/shapes/polygon.lua
-- Polygon shape handler with concave support via triangulation

local constants = require "engine.core.constants"

local polygon = {}

function polygon.create(world, object)
    if not object.polygon then return false, nil end

    local vertices = {}
    for _, point in ipairs(object.polygon) do
        table.insert(vertices, point.x)
        table.insert(vertices, point.y)
    end

    -- ALWAYS triangulate for concave support (Box2D silently converts concave to convex hull)
    -- Only skip triangulation for simple triangles
    local point_count = #object.polygon

    -- Skip triangulation for triangles (already convex)
    if point_count == 3 then
        return pcall(world.newPolygonCollider, world, vertices, {
            body_type = 'static',
            collision_class = 'Wall'
        })
    end

    -- For 4+ points, always triangulate to ensure proper concave handling
    local triangles_success, triangles = pcall(love.math.triangulate, vertices)
    if not triangles_success or not triangles then
        print("Triangulation failed - using bounding box fallback")
        -- Fallback to rectangle using bounding box
        local min_x, min_y = math.huge, math.huge
        local max_x, max_y = -math.huge, -math.huge
        for i = 1, #vertices, 2 do
            min_x = math.min(min_x, vertices[i])
            min_y = math.min(min_y, vertices[i + 1])
            max_x = math.max(max_x, vertices[i])
            max_y = math.max(max_y, vertices[i + 1])
        end
        local rect_wall = world:newRectangleCollider(
            object.x + min_x,
            object.y + min_y,
            max_x - min_x,
            max_y - min_y
        )
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

return polygon

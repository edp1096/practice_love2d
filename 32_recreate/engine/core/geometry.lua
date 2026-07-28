local util = require "engine.core.util"

local geometry = {}

local function distanceToSegmentSquared(px, py, ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local length_squared = dx * dx + dy * dy
    if length_squared == 0 then
        local point_dx = px - ax
        local point_dy = py - ay
        return point_dx * point_dx + point_dy * point_dy
    end

    local projection =
        ((px - ax) * dx + (py - ay) * dy) / length_squared
    projection = util.clamp(projection, 0, 1)
    local closest_x = ax + projection * dx
    local closest_y = ay + projection * dy
    local point_dx = px - closest_x
    local point_dy = py - closest_y
    return point_dx * point_dx + point_dy * point_dy
end

function geometry.distanceToSegmentSquared(px, py, ax, ay, bx, by)
    return distanceToSegmentSquared(px, py, ax, ay, bx, by)
end

function geometry.sweptCirclesIntersect(
    start_x,
    start_y,
    end_x,
    end_y,
    moving_radius,
    target_x,
    target_y,
    target_radius
)
    local combined = moving_radius + target_radius
    return distanceToSegmentSquared(
        target_x,
        target_y,
        start_x,
        start_y,
        end_x,
        end_y
    ) <= combined * combined
end

function geometry.pointInPolygon(x, y, points)
    local inside = false
    local previous = points[#points]
    for _, current in ipairs(points) do
        local crosses =
            (current.y > y) ~= (previous.y > y) and
            x < (previous.x - current.x) * (y - current.y) /
                (previous.y - current.y) + current.x
        if crosses then inside = not inside end
        previous = current
    end
    return inside
end

function geometry.circleIntersectsPolygon(x, y, radius, points)
    if geometry.pointInPolygon(x, y, points) then return true end
    local radius_squared = radius * radius
    local previous = points[#points]
    for _, current in ipairs(points) do
        if distanceToSegmentSquared(
            x,
            y,
            previous.x,
            previous.y,
            current.x,
            current.y
        ) < radius_squared then
            return true
        end
        previous = current
    end
    return false
end

function geometry.circleIntersectsRectangle(x, y, radius, shape)
    local half_width = shape.width / 2
    local half_height = shape.height / 2
    local closest_x = util.clamp(
        x,
        shape.x - half_width,
        shape.x + half_width
    )
    local closest_y = util.clamp(
        y,
        shape.y - half_height,
        shape.y + half_height
    )
    local dx = x - closest_x
    local dy = y - closest_y
    return dx * dx + dy * dy < radius * radius
end

function geometry.circleIntersectsShape(x, y, radius, shape)
    if shape.type == "rectangle" then
        return geometry.circleIntersectsRectangle(x, y, radius, shape)
    elseif shape.type == "polygon" then
        return geometry.circleIntersectsPolygon(x, y, radius, shape.points)
    end
    return false
end

function geometry.bodyPoints(transform, body)
    local result = {}
    for index, point in ipairs(body.points or {}) do
        result[index] = {
            x = transform.x + point.x,
            y = transform.y + point.y,
        }
    end
    return result
end

return geometry

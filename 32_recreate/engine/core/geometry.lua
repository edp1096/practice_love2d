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

function geometry.sweptCircleFraction(
    start_x,
    start_y,
    end_x,
    end_y,
    moving_radius,
    target_x,
    target_y,
    target_radius
)
    local radius = moving_radius + target_radius
    local offset_x = start_x - target_x
    local offset_y = start_y - target_y
    local c =
        offset_x * offset_x + offset_y * offset_y - radius * radius
    if c <= 0 then return 0 end

    local delta_x = end_x - start_x
    local delta_y = end_y - start_y
    local a = delta_x * delta_x + delta_y * delta_y
    if a <= 1e-12 then return nil end
    local b = 2 * (offset_x * delta_x + offset_y * delta_y)
    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then return nil end
    local fraction = (-b - math.sqrt(discriminant)) / (2 * a)
    if fraction < 0 or fraction > 1 then return nil end
    return fraction
end

local function minimumFraction(current, candidate)
    if candidate == nil then return current end
    if current == nil or candidate < current then return candidate end
    return current
end

local function sweptCircleSegmentFraction(
    start_x,
    start_y,
    end_x,
    end_y,
    radius,
    first,
    second
)
    local result = geometry.sweptCircleFraction(
        start_x,
        start_y,
        end_x,
        end_y,
        radius,
        first.x,
        first.y,
        0
    )
    result = minimumFraction(result, geometry.sweptCircleFraction(
        start_x,
        start_y,
        end_x,
        end_y,
        radius,
        second.x,
        second.y,
        0
    ))

    local edge_x = second.x - first.x
    local edge_y = second.y - first.y
    local edge_length = math.sqrt(edge_x * edge_x + edge_y * edge_y)
    if edge_length <= 1e-12 then return result end
    local normal_x = -edge_y / edge_length
    local normal_y = edge_x / edge_length
    local start_distance =
        (start_x - first.x) * normal_x +
        (start_y - first.y) * normal_y
    local velocity_x = end_x - start_x
    local velocity_y = end_y - start_y
    local normal_velocity =
        velocity_x * normal_x + velocity_y * normal_y
    if math.abs(normal_velocity) <= 1e-12 then return result end

    for _, boundary in ipairs({-radius, radius}) do
        local fraction =
            (boundary - start_distance) / normal_velocity
        if fraction >= 0 and fraction <= 1 then
            local x = start_x + velocity_x * fraction
            local y = start_y + velocity_y * fraction
            local projection =
                ((x - first.x) * edge_x +
                 (y - first.y) * edge_y) /
                (edge_length * edge_length)
            if projection >= 0 and projection <= 1 then
                result = minimumFraction(result, fraction)
            end
        end
    end
    return result
end

function geometry.sweptCirclePolygonFraction(
    start_x,
    start_y,
    end_x,
    end_y,
    radius,
    points
)
    if geometry.circleIntersectsPolygon(
        start_x,
        start_y,
        radius,
        points
    ) then
        return 0
    end
    local result
    local previous = points[#points]
    for _, current in ipairs(points) do
        result = minimumFraction(
            result,
            sweptCircleSegmentFraction(
                start_x,
                start_y,
                end_x,
                end_y,
                radius,
                previous,
                current
            )
        )
        previous = current
    end
    return result
end

function geometry.sweptCircleShapeFraction(
    start_x,
    start_y,
    end_x,
    end_y,
    radius,
    shape
)
    local points
    if shape.type == "rectangle" then
        local half_width = shape.width / 2
        local half_height = shape.height / 2
        points = {
            {x = shape.x - half_width, y = shape.y - half_height},
            {x = shape.x + half_width, y = shape.y - half_height},
            {x = shape.x + half_width, y = shape.y + half_height},
            {x = shape.x - half_width, y = shape.y + half_height},
        }
    elseif shape.type == "polygon" then
        points = shape.points
    else
        return nil
    end
    return geometry.sweptCirclePolygonFraction(
        start_x,
        start_y,
        end_x,
        end_y,
        radius,
        points
    )
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

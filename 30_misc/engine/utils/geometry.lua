-- engine/utils/geometry.lua
-- Geometry utilities for collision detection and spatial testing

local geometry = {}

-- Point-in-polygon test using ray casting algorithm
-- @param polygon: array of {x, y} points
-- @param x, y: point to test
-- @return boolean
function geometry.pointInPolygon(polygon, x, y)
    local inside = false
    local j = #polygon
    for i = 1, #polygon do
        local pi, pj = polygon[i], polygon[j]
        if (pi.y > y) ~= (pj.y > y) and
           x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- Point-in-rectangle test
-- @param rect: table with x, y, width, height
-- @param x, y: point to test
-- @return boolean
function geometry.pointInRectangle(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.width and
           y >= rect.y and y <= rect.y + rect.height
end

-- Point-in-bounds test (for quick rejection before expensive tests)
-- @param bounds: table with min_x, min_y, max_x, max_y
-- @param x, y: point to test
-- @return boolean
function geometry.pointInBounds(bounds, x, y)
    return x >= bounds.min_x and x <= bounds.max_x and
           y >= bounds.min_y and y <= bounds.max_y
end

-- Check if point is in any of the given zones
-- Supports polygon and rectangle shapes
-- @param zones: array of zone objects with shape, polygon/bounds, or x/y/width/height
-- @param x, y: point to test
-- @return boolean
function geometry.pointInZones(zones, x, y)
    if not zones or #zones == 0 then return false end

    for _, zone in ipairs(zones) do
        if zone.shape == "polygon" and zone.polygon then
            -- Polygon zone with optional bounding box optimization
            if zone.bounds then
                if geometry.pointInBounds(zone.bounds, x, y) and
                   geometry.pointInPolygon(zone.polygon, x, y) then
                    return true
                end
            elseif geometry.pointInPolygon(zone.polygon, x, y) then
                return true
            end
        elseif zone.x and zone.width then
            -- Rectangle zone
            if geometry.pointInRectangle(zone, x, y) then
                return true
            end
        end
    end
    return false
end

-- Calculate distance between two points
-- @return distance, dx, dy
function geometry.distance(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy), dx, dy
end

-- Calculate bounding box from polygon points
-- @param polygon: array of {x, y} points
-- @return bounds table {min_x, min_y, max_x, max_y}
function geometry.polygonBounds(polygon)
    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge

    for _, p in ipairs(polygon) do
        min_x = math.min(min_x, p.x)
        min_y = math.min(min_y, p.y)
        max_x = math.max(max_x, p.x)
        max_y = math.max(max_y, p.y)
    end

    return { min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y }
end

return geometry

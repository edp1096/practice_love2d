-- systems/world/stairs.lua
-- Stair system for topdown mode (visual Y offset based on position)

local stairs = {}

-- Point-in-polygon test using ray casting algorithm
local function pointInPolygon(x, y, polygon)
    local n = #polygon
    local inside = false

    local j = n
    for i = 1, n do
        local xi, yi = polygon[i].x, polygon[i].y
        local xj, yj = polygon[j].x, polygon[j].y

        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end

    return inside
end

-- Check if entity is on stairs and return stair info (topdown only)
-- Returns: stair table with hill_direction, or nil if not on stairs
function stairs.getStairInfo(self, entity_x, entity_y)
    if not self.stairs or #self.stairs == 0 then
        return nil
    end

    for _, stair in ipairs(self.stairs) do
        local is_inside = false

        if stair.shape == "polygon" and stair.polygon then
            -- Quick bounding box rejection
            local b = stair.bounds
            local in_bounds = entity_x >= b.min_x and entity_x <= b.max_x and
                              entity_y >= b.min_y and entity_y <= b.max_y
            if in_bounds then
                -- Detailed polygon test
                is_inside = pointInPolygon(entity_x, entity_y, stair.polygon)
            end
        else
            -- Rectangle check
            is_inside = entity_x >= stair.x and entity_x <= stair.x + stair.width and
                        entity_y >= stair.y and entity_y <= stair.y + stair.height
        end

        if is_inside then
            return stair
        end
    end

    return nil
end

-- Modify velocity for stair movement (45-degree diagonal)
-- When on stairs, horizontal movement also affects vertical movement
--
-- Guardrail system:
--   - For left/right stairs: block pure vertical (up/down) movement to prevent side exit
--   - For up/down stairs: block pure horizontal (left/right) movement to prevent side exit
--   - Player can only exit through the ends of the stairs (along stair direction)
--
-- hill_direction meanings:
--   "left"  = left side is higher (going left = uphill, going right = downhill)
--   "right" = right side is higher (going right = uphill, going left = downhill)
--   "up"    = top side is higher (going up = uphill, going down = downhill)
--   "down"  = bottom side is higher (going down = uphill, going up = downhill)
function stairs.adjustVelocityForStairs(self, vx, vy, entity_x, entity_y)
    local stair = self:getStairInfo(entity_x, entity_y)
    if not stair then
        return vx, vy, nil
    end

    local adjusted_vx = vx
    local adjusted_vy = vy

    if stair.hill_direction == "left" or stair.hill_direction == "right" then
        -- Horizontal stairs (left/right): primary movement is horizontal
        -- Guardrail: block pure vertical input to prevent walking off sides

        if stair.hill_direction == "left" then
            -- Left is uphill: vy = vx (going left goes up)
            adjusted_vy = vx
        else  -- right
            -- Right is uphill: vy = -vx (going right goes up)
            adjusted_vy = -vx
        end

        -- Allow vertical exit at stair ends (top/bottom of polygon)
        local bounds = stair.bounds
        if bounds then
            local near_top = entity_y <= bounds.min_y + 10
            local near_bottom = entity_y >= bounds.max_y - 10

            -- At top: allow upward exit (vy < 0 from input)
            if near_top and vy < 0 then
                adjusted_vy = vy + vx
            -- At bottom: allow downward exit (vy > 0 from input)
            elseif near_bottom and vy > 0 then
                adjusted_vy = vy + vx
            end
        end

    elseif stair.hill_direction == "up" or stair.hill_direction == "down" then
        -- Vertical stairs (up/down): slope affects vertical movement only
        -- Horizontal movement (vx) is unchanged
        adjusted_vx = vx

        if stair.hill_direction == "up" then
            -- Up is uphill: going up is slower
            if vy < 0 then
                adjusted_vy = vy * 0.7  -- 30% slower going uphill
            end
        else  -- down
            -- Down is uphill (reversed): going down is slower
            if vy > 0 then
                adjusted_vy = vy * 0.7
            end
        end
    end

    return adjusted_vx, adjusted_vy, stair
end

-- Legacy function for compatibility - returns 0 (no visual offset needed now)
function stairs.getStairOffset(self, entity_x, entity_y)
    return 0
end

return stairs

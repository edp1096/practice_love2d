local geometry = require "engine.core.geometry"
local util = require "engine.core.util"

local feature = {
    id = "geometry",
    requires = {"engine.features.world"},
}

local function validatePoint(point, validator, path)
    if not validator:table(point, path, true) then return end
    validator:keys(point, {"x", "y"}, path)
    validator:number(point.x, path .. ".x", true)
    validator:number(point.y, path .. ".y", true)
end

local function validateShape(shape, validator, path)
    if not validator:table(shape, path, true) then return end
    validator:keys(
        shape,
        {"type", "x", "y", "width", "height", "points"},
        path
    )
    local shape_type = validator:enum(
        shape.type,
        {"rectangle", "polygon"},
        path .. ".type",
        true
    )
    if shape_type == "rectangle" then
        validator:number(shape.x, path .. ".x", true)
        validator:number(shape.y, path .. ".y", true)
        validator:positive(shape.width, path .. ".width", true)
        validator:positive(shape.height, path .. ".height", true)
    elseif shape_type == "polygon" then
        local points = validator:array(
            shape.points,
            path .. ".points",
            true
        )
        if points and #points < 3 then
            validator:error(path .. ".points", "requires at least 3 points")
        end
        for index, point in ipairs(points or {}) do
            validatePoint(
                point,
                validator,
                string.format("%s.points[%d]", path, index)
            )
        end
    end
end

local function validateWalls(walls, validator, path)
    walls = validator:array(walls, path, false)
    local seen = {}
    for index, wall in ipairs(walls or {}) do
        local item_path = string.format("%s[%d]", path, index)
        if validator:table(wall, item_path, true) then
            validator:keys(wall, {"id", "shape"}, item_path)
            local id = validator:string(
                wall.id,
                item_path .. ".id",
                true
            )
            if id and seen[id] then
                validator:error(item_path .. ".id", "duplicates another wall id")
            elseif id then
                seen[id] = true
            end
            validateShape(wall.shape, validator, item_path .. ".shape")
        end
    end
end

local service = {}

function service:validateShape(shape, validator, path)
    validateShape(shape, validator, path)
end

function service:walls(world)
    local state = world.feature_state.geometry
    return state and state.walls or {}
end

function service:circleBlocked(world, x, y, radius)
    for _, wall in ipairs(self:walls(world)) do
        if geometry.circleIntersectsShape(x, y, radius, wall.shape) then
            return true, wall
        end
    end
    return false
end

function service:sweepCircle(
    world,
    start_x,
    start_y,
    end_x,
    end_y,
    radius
)
    local best
    for _, wall in ipairs(self:walls(world)) do
        local fraction = geometry.sweptCircleShapeFraction(
            start_x,
            start_y,
            end_x,
            end_y,
            radius,
            wall.shape
        )
        if fraction ~= nil and
           (not best or fraction < best.fraction or
            (fraction == best.fraction and wall.id < best.wall.id)) then
            best = {
                fraction = fraction,
                wall = wall,
            }
        end
    end
    return best
end

function service:containsEntity(shape, entity)
    local transform = entity and entity.components.transform
    if not transform then return false end
    local body = entity.components.body
    local hurtbox = entity.components["action.hurtbox"]
    local x = transform.x + (hurtbox and hurtbox.offset_x or 0)
    local y = transform.y + (hurtbox and hurtbox.offset_y or 0)
    local radius =
        hurtbox and hurtbox.radius or
        body and body.shape == "circle" and body.radius or
        0
    if not hurtbox and body and body.shape == "rectangle" then
        radius = math.sqrt(
            (body.width / 2) ^ 2 + (body.height / 2) ^ 2
        )
    elseif not hurtbox and body and body.shape == "polygon" then
        for _, point in ipairs(body.points or {}) do
            radius = math.max(
                radius,
                math.sqrt(point.x * point.x + point.y * point.y)
            )
        end
    end
    return geometry.circleIntersectsShape(
        x,
        y,
        radius,
        shape
    )
end

local function drawShape(shape)
    if shape.type == "rectangle" then
        love.graphics.rectangle(
            "line",
            shape.x - shape.width / 2,
            shape.y - shape.height / 2,
            shape.width,
            shape.height
        )
    elseif shape.type == "polygon" then
        local coordinates = {}
        for _, point in ipairs(shape.points) do
            coordinates[#coordinates + 1] = point.x
            coordinates[#coordinates + 1] = point.y
        end
        love.graphics.polygon("line", coordinates)
    end
end

function feature:register(host)
    host:registerService("geometry", service)
    host:registerStageSection("walls", {
        priority = 10,
        validate = validateWalls,
        load = function(world, walls)
            world.feature_state.geometry = {
                walls = util.deepCopy(walls or {}),
            }
            return true
        end,
    })
    host:registerWorldInspector("geometry", function(world)
        return {
            geometry = {
                wall_count = #service:walls(world),
            },
        }
    end)
    host:registerDebugDrawer("geometry", function(world, options)
        if not options.entities then return end
        love.graphics.setColor(1, 0.35, 0.2, 0.88)
        for _, wall in ipairs(service:walls(world)) do
            drawShape(wall.shape)
        end
    end)
end

return feature

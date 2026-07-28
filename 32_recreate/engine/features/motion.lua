local util = require "engine.core.util"
local geometry = require "engine.core.geometry"

local feature = {
    id = "motion",
    requires = {"engine.features.world"},
}

local function validateFacing(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"x", "y"}, path)
    local x = validator:number(config.x, path .. ".x", false) or 1
    local y = validator:number(config.y, path .. ".y", false) or 0
    if x == 0 and y == 0 then
        validator:error(path, "direction must not be zero")
    end
end

local function validateKinematics(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"velocity_x", "velocity_y"}, path)
    validator:number(
        config.velocity_x,
        path .. ".velocity_x",
        false
    )
    validator:number(
        config.velocity_y,
        path .. ".velocity_y",
        false
    )
end

local function overlapsCircleRectangle(x, y, radius, transform, body)
    local half_width = body.width / 2
    local half_height = body.height / 2
    local closest_x = util.clamp(
        x,
        transform.x - half_width,
        transform.x + half_width
    )
    local closest_y = util.clamp(
        y,
        transform.y - half_height,
        transform.y + half_height
    )
    local dx = x - closest_x
    local dy = y - closest_y
    return dx * dx + dy * dy < radius * radius
end

local function overlapsCircles(
    x,
    y,
    radius,
    obstacle_transform,
    obstacle_body
)
    local dx = x - obstacle_transform.x
    local dy = y - obstacle_transform.y
    local combined = radius + obstacle_body.radius
    return dx * dx + dy * dy < combined * combined
end

local function bodiesCanCollide(moving, obstacle)
    return moving.collision_mask_set[obstacle.collision_layer] and
        obstacle.collision_mask_set[moving.collision_layer]
end

local function blocked(world, moving_entity, x, y)
    local body = moving_entity.components.body
    if not body or body.shape ~= "circle" or
       not body.solid or body.static then
        return false
    end

    local stage_geometry = world:service("geometry")
    if body.collision_mask_set.world and stage_geometry and
       stage_geometry:circleBlocked(world, x, y, body.radius) then
        return true
    end

    for _, obstacle in ipairs(world:query("transform", "body")) do
        if obstacle ~= moving_entity and
           not world.pending_removal[obstacle.id] then
            local obstacle_body = obstacle.components.body
            if obstacle_body.solid and
               bodiesCanCollide(body, obstacle_body) then
                if obstacle_body.shape == "circle" and
                   overlapsCircles(
                       x,
                       y,
                       body.radius,
                       obstacle.components.transform,
                       obstacle_body
                   ) then
                    return true
                elseif obstacle_body.shape == "rectangle" and
                   overlapsCircleRectangle(
                       x,
                       y,
                       body.radius,
                       obstacle.components.transform,
                       obstacle_body
                   ) then
                    return true
                elseif obstacle_body.shape == "polygon" and
                       geometry.circleIntersectsPolygon(
                           x,
                           y,
                           body.radius,
                           geometry.bodyPoints(
                               obstacle.components.transform,
                               obstacle_body
                           )
                       ) then
                    return true
                end
            end
        end
    end
    return false
end

local motion = {}

local function advanceAxis(world, entity, axis, delta)
    if delta == 0 then return end
    local transform = entity.components.transform
    local start = transform[axis]
    local target = start + delta
    local target_x = axis == "x" and target or transform.x
    local target_y = axis == "y" and target or transform.y
    if not blocked(world, entity, target_x, target_y) then
        transform[axis] = target
        return
    end

    local low, high = 0, 1
    for _ = 1, 12 do
        local fraction = (low + high) / 2
        local candidate = start + delta * fraction
        local candidate_x =
            axis == "x" and candidate or transform.x
        local candidate_y =
            axis == "y" and candidate or transform.y
        if blocked(world, entity, candidate_x, candidate_y) then
            high = fraction
        else
            low = fraction
        end
    end
    transform[axis] = start + delta * low
end

function motion:facing(entity)
    local facing =
        entity and entity.components and
        entity.components["motion.facing"]
    return facing and facing.x or 1, facing and facing.y or 0
end

function motion:setFacing(entity, x, y)
    local facing =
        entity and entity.components and
        entity.components["motion.facing"]
    if not facing then return false end
    x, y = util.normalize(x, y)
    if x == 0 and y == 0 then return false end
    facing.x, facing.y = x, y
    return true
end

function motion:kinematics(entity)
    return entity and entity.components and
        entity.components["motion.kinematics"] or nil
end

function motion:setVelocity(entity, x, y)
    local kinematics = self:kinematics(entity)
    if not kinematics then return false end
    kinematics.velocity_x = x
    kinematics.velocity_y = y
    kinematics.moving = x ~= 0 or y ~= 0
    return true
end

function motion:move(world, entity, delta_x, delta_y)
    local transform = entity.components.transform
    if not transform then return 0, 0 end
    local start_x, start_y = transform.x, transform.y

    local steps = math.max(
        1,
        math.ceil(math.max(math.abs(delta_x), math.abs(delta_y)) / 4)
    )
    local step_x = delta_x / steps
    local step_y = delta_y / steps
    for _ = 1, steps do
        advanceAxis(world, entity, "x", step_x)
        advanceAxis(world, entity, "y", step_y)
    end

    local body = entity.components.body
    local extent_x, extent_y = 0, 0
    if body and body.shape == "circle" then
        extent_x, extent_y = body.radius, body.radius
    elseif body and body.shape == "rectangle" then
        extent_x, extent_y = body.width / 2, body.height / 2
    end
    transform.x = util.clamp(
        transform.x,
        extent_x,
        world.stage.width - extent_x
    )
    transform.y = util.clamp(
        transform.y,
        extent_y,
        world.stage.height - extent_y
    )
    return transform.x - start_x, transform.y - start_y
end

function feature:register(host)
    host:registerComponent("motion.facing", {
        validate = validateFacing,
        create = function(config)
            local x, y = util.normalize(config.x or 1, config.y or 0)
            return {x = x, y = y}
        end,
    })
    host:registerComponent("motion.kinematics", {
        validate = validateKinematics,
        create = function(config)
            local velocity_x = config.velocity_x or 0
            local velocity_y = config.velocity_y or 0
            return {
                velocity_x = velocity_x,
                velocity_y = velocity_y,
                moving = velocity_x ~= 0 or velocity_y ~= 0,
                grounded = false,
            }
        end,
    })
    host:registerService("motion", motion)
    host:registerEntityInspector("motion", function(entity)
        local facing = entity.components["motion.facing"]
        local kinematics = entity.components["motion.kinematics"]
        if not facing and not kinematics then return end
        local result = {}
        if facing then
            result.facing_x = facing.x
            result.facing_y = facing.y
        end
        if kinematics then
            result.velocity_x = kinematics.velocity_x
            result.velocity_y = kinematics.velocity_y
            result.moving = kinematics.moving
            result.grounded = kinematics.grounded
        end
        return result
    end)
    host:registerDebugDrawer("motion.facing", function(world, options)
        if not options.entities then return end
        for _, entity in ipairs(
            world:query("transform", "motion.facing")
        ) do
            local transform = entity.components.transform
            local facing = entity.components["motion.facing"]
            love.graphics.setColor(1, 0.85, 0.2, 0.9)
            love.graphics.line(
                transform.x,
                transform.y,
                transform.x + facing.x * 24,
                transform.y + facing.y * 24
            )
        end
    end)
end

return feature

local util = require "engine.core.util"

local feature = {
    id = "action.hitbox",
    requires = {"engine.features.motion"},
}

local function validateHurtbox(config, validator, path, partial)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"radius", "offset_x", "offset_y"}, path)
    validator:positive(config.radius, path .. ".radius", not partial)
    validator:number(config.offset_x, path .. ".offset_x", false)
    validator:number(config.offset_y, path .. ".offset_y", false)
end

local function validateHitbox(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "shape", "reach", "arc_degrees",
            "repeat_interval", "max_hits",
        },
        path
    )
    validator:enum(config.shape, {"arc"}, path .. ".shape", true)
    validator:positive(config.reach, path .. ".reach", true)
    local arc =
        validator:number(config.arc_degrees, path .. ".arc_degrees", true)
    if arc and (arc <= 0 or arc > 360) then
        validator:error(
            path .. ".arc_degrees",
            "must be greater than 0 and at most 360"
        )
    end
    local repeat_interval = validator:positive(
        config.repeat_interval,
        path .. ".repeat_interval",
        false
    )
    local max_hits = validator:number(
        config.max_hits,
        path .. ".max_hits",
        false
    )
    if max_hits and (max_hits < 1 or max_hits % 1 ~= 0) then
        validator:error(
            path .. ".max_hits",
            "must be a positive integer"
        )
    end
    if repeat_interval and not max_hits then
        validator:error(
            path .. ".max_hits",
            "is required with repeat_interval"
        )
    elseif max_hits and max_hits > 1 and not repeat_interval then
        validator:error(
            path .. ".repeat_interval",
            "is required when max_hits is greater than 1"
        )
    end
end

local function hurtboxOf(entity)
    return entity and entity.components and
        entity.components["action.hurtbox"] or nil
end

local hitbox_service = {}

function hitbox_service:validate(config, validator, path)
    validateHitbox(config, validator, path)
end

function hitbox_service:radius(source, hitbox)
    local source_hurtbox = hurtboxOf(source)
    return (source_hurtbox and source_hurtbox.radius or 0) +
        hitbox.reach
end

function hitbox_service:contains(source, target, hitbox)
    local source_transform = source.components.transform
    local target_transform = target.components.transform
    local source_hurtbox = hurtboxOf(source)
    local target_hurtbox = hurtboxOf(target)
    if not source_transform or not target_transform or
       not target_hurtbox then
        return false
    end

    local source_x = source_transform.x +
        (source_hurtbox and source_hurtbox.offset_x or 0)
    local source_y = source_transform.y +
        (source_hurtbox and source_hurtbox.offset_y or 0)
    local target_x = target_transform.x + target_hurtbox.offset_x
    local target_y = target_transform.y + target_hurtbox.offset_y
    local dx = target_x - source_x
    local dy = target_y - source_y
    local distance = util.length(dx, dy)
    if distance >
       self:radius(source, hitbox) + target_hurtbox.radius then
        return false
    end
    if hitbox.arc_degrees >= 360 or distance == 0 then return true end

    local direction_x, direction_y = util.normalize(dx, dy)
    local facing_x, facing_y =
        source.components["motion.facing"] and
            source.components["motion.facing"].x or 1,
        source.components["motion.facing"] and
            source.components["motion.facing"].y or 0
    local dot = facing_x * direction_x + facing_y * direction_y
    return dot >= math.cos(math.rad(hitbox.arc_degrees / 2))
end

function feature:register(host)
    host:registerComponent("action.hurtbox", {
        validate = validateHurtbox,
        create = function(config)
            return {
                radius = config.radius or 12,
                offset_x = config.offset_x or 0,
                offset_y = config.offset_y or 0,
            }
        end,
    })

    host:registerService("action.hitbox", hitbox_service)
    host:registerEntityInspector("action.hurtbox", function(entity)
        local hurtbox = hurtboxOf(entity)
        if not hurtbox then return end
        return {
            hurtbox_radius = hurtbox.radius,
            hurtbox_offset_x = hurtbox.offset_x,
            hurtbox_offset_y = hurtbox.offset_y,
        }
    end)
    host:registerDebugDrawer(
        "action.hurtbox",
        function(world, options)
            if not options.entities then return end
            for _, entity in ipairs(
                world:query("transform", "action.hurtbox")
            ) do
                local transform = entity.components.transform
                local hurtbox = hurtboxOf(entity)
                love.graphics.setColor(1, 0.2, 0.75, 0.9)
                love.graphics.circle(
                    "line",
                    transform.x + hurtbox.offset_x,
                    transform.y + hurtbox.offset_y,
                    hurtbox.radius
                )
            end
        end
    )
end

return feature

local util = require "engine.core.util"

local feature = {
    id = "action.knockback",
    requires = {
        "engine.features.motion",
        "engine.features.action.health",
    },
}

local function validateComponent(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"resistance"}, path)
    local resistance =
        validator:number(config.resistance, path .. ".resistance", false)
    if resistance and (resistance < 0 or resistance > 1) then
        validator:error(
            path .. ".resistance",
            "must be between 0 and 1"
        )
    end
end

local function validateAction(action, validator, path)
    validator:keys(action, {"type", "distance", "duration"}, path)
    validator:positive(action.distance, path .. ".distance", true)
    validator:positive(action.duration, path .. ".duration", true)
end

local function knockbackOf(entity)
    return entity and entity.components and
        entity.components["action.knockback"] or nil
end

local function directionFrom(world, source, target)
    local source_transform =
        source and source.components and source.components.transform
    local target_transform =
        target and target.components and target.components.transform
    if source_transform and target_transform then
        local x, y = util.normalize(
            target_transform.x - source_transform.x,
            target_transform.y - source_transform.y
        )
        if x ~= 0 or y ~= 0 then return x, y end
    end
    return world:service("motion"):facing(source)
end

local movement_system = {
    id = "action.knockback.integrate",
    phase = "movement",
    order = 10,
}

function movement_system:update(world, dt)
    for _, entity in ipairs(
        world:query("transform", "action.knockback")
    ) do
        local knockback = knockbackOf(entity)
        if knockback.remaining > 0 then
            local step = math.min(dt, knockback.remaining)
            world:service("motion"):move(
                world,
                entity,
                knockback.velocity_x * step,
                knockback.velocity_y * step
            )
            world:service("motion"):setVelocity(
                entity,
                knockback.velocity_x,
                knockback.velocity_y
            )
            knockback.remaining =
                util.countdown(knockback.remaining, dt)
            if knockback.remaining == 0 then
                knockback.velocity_x = 0
                knockback.velocity_y = 0
                world:service("motion"):setVelocity(entity, 0, 0)
                world.events:emit("actor.knockback_finished", {
                    entity_id = entity.id,
                })
            end
        end
    end
end

local draw_system = {
    id = "action.knockback.feedback",
    draw_order = 25,
}

function draw_system:draw(world)
    for _, entity in ipairs(
        world:query("transform", "action.knockback")
    ) do
        local knockback = knockbackOf(entity)
        if knockback.remaining > 0 then
            local transform = entity.components.transform
            local direction_x, direction_y = util.normalize(
                knockback.velocity_x,
                knockback.velocity_y
            )
            love.graphics.setColor(1, 0.55, 0.12, 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.line(
                transform.x,
                transform.y,
                transform.x + direction_x * 28,
                transform.y + direction_y * 28
            )
            love.graphics.setLineWidth(1)
        end
    end
end

function feature:register(host)
    host:registerComponent("action.knockback", {
        validate = validateComponent,
        create = function(config)
            return {
                resistance = config.resistance or 0,
                remaining = 0,
                velocity_x = 0,
                velocity_y = 0,
            }
        end,
    })
    host.services.lifecycle:registerDeathHandler(
        "action.knockback",
        40,
        function(entity)
            local knockback = knockbackOf(entity)
            if knockback then
                knockback.remaining = 0
                knockback.velocity_x = 0
                knockback.velocity_y = 0
            end
        end
    )

    host.rules:registerAction("knockback", {
        validate = validateAction,
        execute = function(action, context)
            local target = context.target
            local knockback = knockbackOf(target)
            if not knockback or target.dead then
                return false,
                    "knockback target has no live knockback component"
            end
            local distance =
                action.distance * (1 - knockback.resistance)
            if distance <= 0 then
                context.events:emit("actor.knockback_resisted", {
                    target_id = target.id,
                })
                return {
                    applied = false,
                    resisted = true,
                }
            end

            local direction_x, direction_y =
                directionFrom(context.world, context.source, target)
            knockback.remaining = action.duration
            knockback.velocity_x =
                direction_x * distance / action.duration
            knockback.velocity_y =
                direction_y * distance / action.duration
            context.events:emit("actor.knockback_started", {
                source_id =
                    context.source and context.source.id or nil,
                target_id = target.id,
                distance = distance,
                duration = action.duration,
            })
            return {
                applied = true,
                distance = distance,
                duration = action.duration,
            }
        end,
    })

    local function gate(entity)
        local knockback = knockbackOf(entity)
        if knockback and knockback.remaining > 0 then
            return false, "knockback"
        end
        return true
    end
    host:registerGate("move", "knockback.active", gate)
    host:registerGate("act", "knockback.active", gate)

    host:registerEntityInspector("action.knockback", function(entity)
        local knockback = knockbackOf(entity)
        if not knockback then return end
        return {
            knockback_remaining = knockback.remaining,
            knockback_velocity_x = knockback.velocity_x,
            knockback_velocity_y = knockback.velocity_y,
        }
    end)

    host:registerSystem(movement_system)
    host:registerSystem(draw_system)
end

return feature

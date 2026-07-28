local util = require "engine.core.util"

local feature = {
    id = "action.chase_ai",
    requires = {
        "engine.features.movement.topdown",
        "engine.features.action.combat",
    },
}

local function validateAI(config, validator, path, partial)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {"target_tag", "aggro_range", "attack_distance"},
        path
    )
    validator:string(config.target_tag, path .. ".target_tag", not partial)
    validator:positive(config.aggro_range, path .. ".aggro_range", not partial)
    validator:positive(config.attack_distance, path .. ".attack_distance", false)
end

local function nearestTarget(world, source, tag, maximum_distance)
    local source_transform = source.components.transform
    local nearest = nil
    local nearest_distance = maximum_distance

    for _, candidate in ipairs(world:findByTag(tag)) do
        local transform = candidate.components.transform
        if transform and not candidate.dead and candidate ~= source then
            local distance = util.length(
                transform.x - source_transform.x,
                transform.y - source_transform.y
            )
            if distance < nearest_distance then
                nearest = candidate
                nearest_distance = distance
            end
        end
    end
    return nearest, nearest_distance
end

local ai_system = {
    id = "action.chase_ai.intent",
    phase = "intent",
    order = 0,
}

function ai_system:update(world)
    for _, entity in ipairs(
        world:query(
            "transform",
            "movement.topdown",
            "action.combat",
            "action.chase_ai"
        )
    ) do
        if not entity.dead then
            local ai = entity.components["action.chase_ai"]
            local movement = entity.components["movement.topdown"]
            local target, distance = nearestTarget(
                world,
                entity,
                ai.target_tag,
                ai.aggro_range
            )
            if target then
                local source_transform = entity.components.transform
                local target_transform = target.components.transform
                local dx = target_transform.x - source_transform.x
                local dy = target_transform.y - source_transform.y
                world:service("motion"):setFacing(entity, dx, dy)

                if distance > ai.attack_distance * 0.8 then
                    movement.intent_x, movement.intent_y =
                        util.normalize(dx, dy)
                end
                if distance <= ai.attack_distance then
                    entity.commands.attack = true
                end
            end
        end
    end
end

function feature:register(host)
    host:registerComponent("action.chase_ai", {
        validate = validateAI,
        create = function(config)
            return {
                target_tag = config.target_tag or "player",
                aggro_range = config.aggro_range or 320,
                attack_distance = config.attack_distance or 42,
            }
        end,
    })
    host:registerSystem(ai_system)
end

return feature

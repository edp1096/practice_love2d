local util = require "engine.core.util"

local feature = {
    id = "action.reaction",
    requires = {"engine.features.action.health"},
}

local function validateReaction(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {"hit_invulnerability", "flash_duration"},
        path
    )
    for _, field in ipairs({"hit_invulnerability", "flash_duration"}) do
        local value = validator:number(
            config[field],
            path .. "." .. field,
            false
        )
        if value and value < 0 then
            validator:error(path .. "." .. field, "must not be negative")
        end
    end
end

local function validateDuration(action, validator, path)
    validator:keys(action, {"type", "duration"}, path)
    validator:positive(action.duration, path .. ".duration", true)
end

local function reactionOf(entity)
    return entity and entity.components and
        entity.components["action.reaction"] or nil
end

local reaction_system = {
    id = "action.reaction.timers",
    phase = "resolution",
    order = 0,
}

function reaction_system:update(world, dt)
    for _, entity in ipairs(world:query("action.reaction")) do
        local reaction = reactionOf(entity)
        local was_staggered = reaction.stagger_remaining > 0
        reaction.stagger_remaining =
            util.countdown(reaction.stagger_remaining, dt)
        reaction.invulnerable_remaining =
            util.countdown(reaction.invulnerable_remaining, dt)
        reaction.flash_remaining =
            util.countdown(reaction.flash_remaining, dt)
        if was_staggered and reaction.stagger_remaining == 0 then
            world.events:emit("actor.recovered", {entity_id = entity.id})
        end
    end
end

local reaction_draw_system = {
    id = "action.reaction.feedback",
    draw_order = 24,
}

function reaction_draw_system:draw(world)
    for _, entity in ipairs(
        world:query("transform", "action.reaction")
    ) do
        local transform = entity.components.transform
        local reaction = reactionOf(entity)
        local body = entity.components.body
        local radius = body and body.radius or 14

        if reaction.flash_remaining > 0 then
            local alpha = util.clamp(
                reaction.flash_remaining / reaction.flash_duration,
                0,
                1
            )
            love.graphics.setColor(1, 1, 1, alpha * 0.9)
            love.graphics.setLineWidth(3)
            love.graphics.circle(
                "line",
                transform.x,
                transform.y,
                radius + 5
            )
            love.graphics.setLineWidth(1)
        end
        if reaction.stagger_remaining > 0 then
            love.graphics.setColor(1, 0.35, 0.15, 0.9)
            love.graphics.printf(
                "STAGGER",
                transform.x - 45,
                transform.y - radius - 48,
                90,
                "center"
            )
        end
    end
end

function feature:register(host)
    host:registerComponent("action.reaction", {
        validate = validateReaction,
        create = function(config)
            return {
                hit_invulnerability = config.hit_invulnerability or 0.3,
                flash_duration = config.flash_duration or 0.16,
                stagger_remaining = 0,
                invulnerable_remaining = 0,
                flash_remaining = 0,
            }
        end,
    })

    host.rules:registerAction("stagger", {
        validate = validateDuration,
        execute = function(action, context)
            local target = context.target
            local reaction = reactionOf(target)
            if not reaction or target.dead then
                return false, "stagger target has no live reaction component"
            end
            reaction.stagger_remaining = math.max(
                reaction.stagger_remaining,
                action.duration
            )
            target.commands = {}
            context.events:emit("actor.staggered", {
                source_id = context.source and context.source.id or nil,
                target_id = target.id,
                duration = action.duration,
            })
            return {applied = true, duration = action.duration}
        end,
    })

    host.rules:registerAction("invulnerable", {
        validate = validateDuration,
        execute = function(action, context)
            local reaction = reactionOf(context.target)
            if not reaction then
                return false, "target has no reaction component"
            end
            reaction.invulnerable_remaining = math.max(
                reaction.invulnerable_remaining,
                action.duration
            )
            return {applied = true, duration = action.duration}
        end,
    })

    host.rules:registerActionInterceptor(
        "damage",
        "reaction.invulnerability",
        20,
        function(action, context, nextHandler)
            if context.damage_kind == "periodic" then
                return nextHandler()
            end
            local target = context.target
            local reaction = reactionOf(target)
            if not reaction then return nextHandler() end

            if reaction.invulnerable_remaining > 0 then
                context.events:emit("actor.damage_blocked", {
                    target_id = target.id,
                    source_id =
                        context.source and context.source.id or nil,
                    reason = "invulnerable",
                })
                return {
                    applied = false,
                    blocked = true,
                    reason = "invulnerable",
                    stop_effects = true,
                }
            end

            local result, execute_error = nextHandler()
            if type(result) == "table" and result.applied then
                reaction.invulnerable_remaining =
                    reaction.hit_invulnerability
                reaction.flash_remaining = reaction.flash_duration
            end
            return result, execute_error
        end
    )

    host:registerGate("move", "reaction.stagger", function(entity)
        local reaction = reactionOf(entity)
        if reaction and reaction.stagger_remaining > 0 then
            return false, "staggered"
        end
        return true
    end)
    host:registerGate("act", "reaction.stagger", function(entity)
        local reaction = reactionOf(entity)
        if reaction and reaction.stagger_remaining > 0 then
            return false, "staggered"
        end
        return true
    end)

    host:registerEntityInspector("action.reaction", function(entity)
        local reaction = reactionOf(entity)
        if not reaction then return end
        return {
            stagger_remaining = reaction.stagger_remaining,
            invulnerable_remaining = reaction.invulnerable_remaining,
            flash_remaining = reaction.flash_remaining,
        }
    end)

    host:registerSystem(reaction_system)
    host:registerSystem(reaction_draw_system)
end

return feature

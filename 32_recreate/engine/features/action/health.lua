local util = require "engine.core.util"

local feature = {
    id = "action.health",
    requires = {"engine.features.world"},
}

local function validateHealth(config, validator, path, partial)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {"max", "current", "remove_on_death", "death_delay"},
        path
    )
    validator:positive(config.max, path .. ".max", not partial)
    local current = validator:number(config.current, path .. ".current", false)
    if current and current < 0 then
        validator:error(path .. ".current", "must not be negative")
    end
    validator:boolean(
        config.remove_on_death,
        path .. ".remove_on_death",
        false
    )
    local delay =
        validator:number(config.death_delay, path .. ".death_delay", false)
    if delay and delay < 0 then
        validator:error(path .. ".death_delay", "must not be negative")
    end
end

local function validateAmount(action, validator, path)
    validator:keys(action, {"type", "amount"}, path)
    validator:positive(action.amount, path .. ".amount", true)
end

local function validateRevive(action, validator, path)
    validator:keys(action, {"type", "amount"}, path)
    validator:positive(action.amount, path .. ".amount", false)
end

local function healthOf(target)
    return target and target.components and
        target.components["action.health"] or nil
end

local cleanup_system = {
    id = "action.health.cleanup",
    phase = "resolution",
    order = 100,
}

function cleanup_system:update(world, dt)
    for _, entity in ipairs(world:query("action.health")) do
        local health = entity.components["action.health"]
        if entity.dead and health.remove_on_death then
            health.death_timer = util.countdown(health.death_timer, dt)
            if health.death_timer <= 0 then
                world:remove(entity, "defeated")
            end
        end
    end
end

local health_draw_system = {
    id = "action.health.bars",
    draw_order = 20,
}

function health_draw_system:draw(world)
    for _, entity in ipairs(
        world:query("transform", "action.health")
    ) do
        local transform = entity.components.transform
        local health = entity.components["action.health"]
        local body = entity.components.body
        local width =
            body and body.shape == "rectangle" and body.width or
            ((body and body.radius or 12) * 2)
        width = math.max(24, width)
        local y =
            transform.y -
            (body and body.shape == "rectangle" and body.height / 2 or
             (body and body.radius or 12)) - 10
        if entity.components["render.sprite"] then
            y = y - 24
        end

        love.graphics.setColor(0.08, 0.08, 0.1, 0.9)
        love.graphics.rectangle("fill", transform.x - width / 2, y, width, 5)
        love.graphics.setColor(
            health.current / health.max > 0.35 and 0.25 or 0.9,
            health.current / health.max > 0.35 and 0.85 or 0.2,
            0.2,
            1
        )
        love.graphics.rectangle(
            "fill",
            transform.x - width / 2,
            y,
            width * util.clamp(health.current / health.max, 0, 1),
            5
        )
    end
end

function feature:register(host)
    local lifecycle = {
        death_handlers = {},
        revive_handlers = {},
    }

    local function registerHandler(registry, name, priority, handler)
        assert(
            type(name) == "string" and name ~= "",
            "lifecycle handler name is required"
        )
        assert(
            type(handler) == "function",
            "lifecycle handler is required"
        )
        for _, existing in ipairs(registry) do
            assert(
                existing.name ~= name,
                "duplicate lifecycle handler: " .. name
            )
        end
        registry[#registry + 1] = {
            name = name,
            priority = priority or 100,
            handler = handler,
        }
        table.sort(registry, function(left, right)
            if left.priority ~= right.priority then
                return left.priority < right.priority
            end
            return left.name < right.name
        end)
    end

    function lifecycle:registerDeathHandler(name, priority, handler)
        registerHandler(self.death_handlers, name, priority, handler)
    end

    function lifecycle:registerReviveHandler(name, priority, handler)
        registerHandler(self.revive_handlers, name, priority, handler)
    end

    function lifecycle:kill(world, target, source, details)
        local health = healthOf(target)
        if not health or target.dead then
            return false
        end
        details = details or {}
        target.dead = true
        target.life_state = "dying"
        target.commands = {}
        health.current = 0
        health.death_timer = health.death_delay
        local motion = world:service("motion")
        if motion then motion:setVelocity(target, 0, 0) end
        for _, handler in ipairs(self.death_handlers) do
            handler.handler(target, world, source, details)
        end
        world.events:emit("actor.killed", {
            source_id = source and source.id or nil,
            target_id = target.id,
            actor_id = target.actor_id,
            ability_id = details.ability_id,
            damage_kind = details.damage_kind,
            debug = details.debug == true,
        })
        return true
    end

    function lifecycle:revive(world, target, amount, source)
        local health = healthOf(target)
        if not health then
            return nil, "revive target has no health component"
        end
        if not target.dead then
            return {
                applied = false,
                reason = "already_alive",
                health = health.current,
            }
        end
        health.current = util.clamp(amount or health.max, 1, health.max)
        health.death_timer = health.death_delay
        target.dead = false
        target.life_state = "alive"
        target.commands = {}
        for _, handler in ipairs(self.revive_handlers) do
            handler.handler(target, world, source)
        end
        world.events:emit("actor.revived", {
            source_id = source and source.id or nil,
            target_id = target.id,
            health = health.current,
        })
        return {
            applied = true,
            health = health.current,
        }
    end

    function lifecycle:setHealth(world, target, value, source)
        local health = healthOf(target)
        if not health then
            return nil, "target has no health component"
        end
        if type(value) ~= "number" or value ~= value or
           value == math.huge or value == -math.huge then
            return nil, "health value must be a finite number"
        end
        value = util.clamp(value, 0, health.max)
        return world:transaction(function()
            if value == health.current and
               target.dead == (value == 0) then
                return {
                    applied = false,
                    health = value,
                }
            end
            if value == 0 then
                if target.dead then
                    health.current = 0
                    return {applied = false, health = 0}
                end
                return world:execute({
                    type = "damage",
                    amount = health.current,
                }, {
                    source = source,
                    target = target,
                    debug = true,
                })
            elseif target.dead then
                return world:execute({
                    type = "revive",
                    amount = value,
                }, {
                    source = source,
                    target = target,
                    debug = true,
                })
            elseif value > health.current then
                return world:execute({
                    type = "heal",
                    amount = value - health.current,
                }, {
                    source = source,
                    target = target,
                    debug = true,
                })
            end
            return world:execute({
                type = "damage",
                amount = health.current - value,
            }, {
                source = source,
                target = target,
                debug = true,
            })
        end)
    end

    host:registerService("lifecycle", lifecycle)
    host:registerComponent("action.health", {
        validate = validateHealth,
        create = function(config, entity)
            local maximum = config.max or 1
            local current =
                util.clamp(config.current or maximum, 0, maximum)
            if current == 0 then
                entity.dead = true
                entity.life_state = "dying"
            end
            return {
                max = maximum,
                current = current,
                remove_on_death = config.remove_on_death ~= false,
                death_delay = config.death_delay or 0.25,
                death_timer = config.death_delay or 0.25,
            }
        end,
    })

    host.rules:registerAction("damage", {
        validate = validateAmount,
        execute = function(action, context)
            local target = context.target
            local health = healthOf(target)
            if not health or target.dead then
                return false, "damage target has no live health component"
            end

            local previous = health.current
            health.current = util.clamp(
                health.current - action.amount,
                0,
                health.max
            )
            context.events:emit("actor.damaged", {
                source_id = context.source and context.source.id or nil,
                target_id = target.id,
                amount = previous - health.current,
                health = health.current,
                ability_id = context.ability and context.ability.id or nil,
                damage_kind = context.damage_kind,
                debug = context.debug == true,
            })

            if health.current == 0 and not target.dead then
                lifecycle:kill(
                    context.world,
                    target,
                    context.source,
                    {
                        ability_id =
                            context.ability and context.ability.id or nil,
                        damage_kind = context.damage_kind,
                        debug = context.debug == true,
                    }
                )
            end
            return {
                applied = true,
                amount = previous - health.current,
                killed = target.dead,
                stop_effects = target.dead,
            }
        end,
    })

    host.rules:registerAction("heal", {
        validate = validateAmount,
        execute = function(action, context)
            local target = context.target
            local health = healthOf(target)
            if not health or target.dead then
                return false,
                    "heal target has no live health component; use revive"
            end
            local previous = health.current
            health.current = util.clamp(
                health.current + action.amount,
                0,
                health.max
            )
            context.events:emit("actor.healed", {
                source_id = context.source and context.source.id or nil,
                target_id = target.id,
                amount = health.current - previous,
                health = health.current,
            })
            return {
                applied = true,
                amount = health.current - previous,
            }
        end,
    })

    host.rules:registerAction("revive", {
        validate = validateRevive,
        execute = function(action, context)
            return lifecycle:revive(
                context.world,
                context.target,
                action.amount,
                context.source
            )
        end,
    })

    host.rules:registerCondition("health_at_most", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "value"}, path)
            validator:number(condition.value, path .. ".value", true)
        end,
        evaluate = function(condition, context)
            local health = healthOf(context.target)
            return health ~= nil and health.current <= condition.value
        end,
    })

    host:registerEntityInspector("action.health", function(entity)
        local health = healthOf(entity)
        if not health then return end
        return {
            health = health.current,
            max_health = health.max,
        }
    end)

    host:registerSystem(cleanup_system)
    host:registerSystem(health_draw_system)
end

return feature

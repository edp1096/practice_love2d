local util = require "engine.core.util"

local feature = {
    id = "action.parry",
    requires = {
        "engine.features.control",
        "engine.features.motion",
        "engine.features.action.reaction",
        "engine.features.action.hitstop",
    },
}

local function validateParry(config, validator, path, _, host)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "input", "window", "perfect_window", "cooldown",
            "success_cooldown", "arc_degrees", "stagger",
            "perfect_stagger", "hitstop", "perfect_hitstop",
        },
        path
    )

    local input =
        validator:string(config.input, path .. ".input", false) or "parry"
    if not host.input:hasAction(input) then
        validator:error(
            path .. ".input",
            "references missing input action '" .. input .. "'"
        )
    end

    local window =
        validator:positive(config.window, path .. ".window", false) or 0.32
    local perfect = validator:positive(
        config.perfect_window,
        path .. ".perfect_window",
        false
    ) or 0.12
    if perfect > window then
        validator:error(
            path .. ".perfect_window",
            "must not exceed the full parry window"
        )
    end
    for _, field in ipairs({
        "cooldown", "success_cooldown", "stagger", "perfect_stagger",
        "hitstop", "perfect_hitstop",
    }) do
        local value =
            validator:number(config[field], path .. "." .. field, false)
        if value and value < 0 then
            validator:error(path .. "." .. field, "must not be negative")
        elseif value and
               (field == "hitstop" or field == "perfect_hitstop") and
               value > 0.25 then
            validator:error(
                path .. "." .. field,
                "must not exceed 0.25 seconds"
            )
        end
    end
    local arc =
        validator:number(config.arc_degrees, path .. ".arc_degrees", false)
    if arc and (arc <= 0 or arc > 360) then
        validator:error(
            path .. ".arc_degrees",
            "must be greater than 0 and at most 360"
        )
    end
end

local function parryOf(entity)
    return entity and entity.components and
        entity.components["action.parry"] or nil
end

local function sourceIsInArc(target, source, parry)
    if parry.arc_degrees >= 360 then return true end
    local target_transform = target.components.transform
    local source_transform = source and source.components.transform
    if not target_transform or not source_transform then return false end

    local dx = source_transform.x - target_transform.x
    local dy = source_transform.y - target_transform.y
    local direction_x, direction_y = util.normalize(dx, dy)
    local facing = target.components["motion.facing"]
    local facing_x = facing and facing.x or 1
    local facing_y = facing and facing.y or 0
    local dot = facing_x * direction_x + facing_y * direction_y
    return dot >= math.cos(math.rad(parry.arc_degrees / 2))
end

local input_system = {
    id = "action.parry.player_input",
    phase = "input",
    order = 20,
}

function input_system:update(world)
    local input = world.host.input
    for _, entity in ipairs(
        world:query("control.player", "action.parry")
    ) do
        local parry = parryOf(entity)
        local combat = entity.components["action.combat"]
        if not entity.dead and input:wasPressed(parry.input) and
           parry.cooldown_remaining <= 0 and not parry.active and
           not (combat and combat.active) and
           world:allows(entity, "act") then
            parry.active = true
            parry.remaining = parry.window
            parry.last_perfect = false
            world.events:emit("parry.started", {
                entity_id = entity.id,
                window = parry.window,
            })
        end
    end
end

local timer_system = {
    id = "action.parry.timers",
    phase = "resolution",
    order = 10,
}

function timer_system:update(world, dt)
    for _, entity in ipairs(world:query("action.parry")) do
        local parry = parryOf(entity)
        parry.cooldown_remaining =
            util.countdown(parry.cooldown_remaining, dt)
        parry.success_remaining =
            util.countdown(parry.success_remaining, dt)
        if parry.active then
            parry.remaining = util.countdown(parry.remaining, dt)
            if parry.remaining <= 0 then
                parry.active = false
                parry.remaining = 0
                parry.cooldown_remaining = parry.cooldown
                world.events:emit("parry.expired", {
                    entity_id = entity.id,
                })
            end
        end
    end
end

local draw_system = {
    id = "action.parry.feedback",
    draw_order = 26,
}

function draw_system:draw(world)
    for _, entity in ipairs(
        world:query("transform", "action.parry")
    ) do
        local parry = parryOf(entity)
        local transform = entity.components.transform
        local body = entity.components.body
        local radius = (body and body.radius or 14) + 12
        if parry.active then
            local pulse = 0.45 + 0.15 *
                math.sin(world.time * 20)
            love.graphics.setColor(0.25, 0.65, 1, pulse)
            love.graphics.circle(
                "fill",
                transform.x,
                transform.y,
                radius
            )
            love.graphics.setColor(0.55, 0.85, 1, 0.95)
            love.graphics.setLineWidth(3)
            love.graphics.circle(
                "line",
                transform.x,
                transform.y,
                radius
            )
            love.graphics.setLineWidth(1)
        end
        if parry.success_remaining > 0 then
            love.graphics.setColor(
                parry.last_perfect and 1 or 0.45,
                parry.last_perfect and 0.9 or 0.8,
                parry.last_perfect and 0.2 or 1,
                1
            )
            love.graphics.printf(
                parry.last_perfect and "PERFECT PARRY" or "PARRY",
                transform.x - 75,
                transform.y - radius - 56,
                150,
                "center"
            )
        end
    end
end

function feature:register(host)
    host:registerComponent("action.parry", {
        validate = function(config, validator, path, partial)
            validateParry(config, validator, path, partial, host)
        end,
        create = function(config)
            return {
                input = config.input or "parry",
                window = config.window or 0.32,
                perfect_window = config.perfect_window or 0.12,
                cooldown = config.cooldown or 0.75,
                success_cooldown = config.success_cooldown or 0.18,
                arc_degrees = config.arc_degrees or 170,
                stagger = config.stagger or 0.55,
                perfect_stagger = config.perfect_stagger or 1.1,
                hitstop = config.hitstop or 0.035,
                perfect_hitstop = config.perfect_hitstop or 0.06,
                active = false,
                remaining = 0,
                cooldown_remaining = 0,
                success_remaining = 0,
                last_perfect = false,
            }
        end,
    })

    host.rules:registerActionInterceptor(
        "damage",
        "parry.guard",
        10,
        function(action, context, nextHandler)
            if context.damage_kind == "periodic" then
                return nextHandler()
            end
            local target = context.target
            local source = context.source
            local parry = parryOf(target)
            if not parry or not parry.active then
                return nextHandler()
            end
            if not sourceIsInArc(target, source, parry) then
                parry.active = false
                parry.remaining = 0
                parry.cooldown_remaining = parry.cooldown
                return nextHandler()
            end

            local elapsed = parry.window - parry.remaining
            local perfect = elapsed <= parry.perfect_window
            parry.active = false
            parry.remaining = 0
            parry.cooldown_remaining = parry.success_cooldown
            parry.success_remaining = 0.5
            parry.last_perfect = perfect

            if source then
                context.world:execute({
                    type = "stagger",
                    duration = perfect and
                        parry.perfect_stagger or parry.stagger,
                }, {
                    source = target,
                    target = source,
                })
            end
            local hitstop = perfect and
                parry.perfect_hitstop or parry.hitstop
            if hitstop > 0 then
                context.world:execute({
                    type = "hitstop",
                    duration = hitstop,
                }, {
                    source = target,
                    target = source,
                })
            end
            context.events:emit("attack.parried", {
                source_id = source and source.id or nil,
                target_id = target.id,
                perfect = perfect,
                damage_prevented = action.amount,
            })
            return {
                applied = false,
                blocked = true,
                parried = true,
                perfect = perfect,
                stop_effects = true,
            }
        end
    )

    host:registerGate("move", "parry.active", function(entity)
        local parry = parryOf(entity)
        if parry and parry.active then return false, "parrying" end
        return true
    end)
    host:registerGate("act", "parry.active", function(entity)
        local parry = parryOf(entity)
        if parry and parry.active then return false, "parrying" end
        return true
    end)

    host:registerEntityInspector("action.parry", function(entity)
        local parry = parryOf(entity)
        if not parry then return end
        return {
            parry_active = parry.active,
            parry_remaining = parry.remaining,
            parry_cooldown = parry.cooldown_remaining,
            parry_success_remaining = parry.success_remaining,
            parry_perfect = parry.last_perfect,
        }
    end)

    host:registerSystem(input_system)
    host:registerSystem(timer_system)
    host:registerSystem(draw_system)
end

return feature

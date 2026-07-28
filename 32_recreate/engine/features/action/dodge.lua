local util = require "engine.core.util"

local feature = {
    id = "action.dodge",
    requires = {
        "engine.features.movement.topdown",
        "engine.features.action.reaction",
    },
}

local function validateDodge(config, validator, path, _, host)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "input", "duration", "distance",
            "invulnerability", "cooldown",
        },
        path
    )
    local input =
        validator:string(config.input, path .. ".input", false) or "dodge"
    if not host.input:hasAction(input) then
        validator:error(
            path .. ".input",
            "references missing input action '" .. input .. "'"
        )
    end
    local duration =
        validator:positive(config.duration, path .. ".duration", false) or 0.22
    validator:positive(config.distance, path .. ".distance", false)
    local invulnerability = validator:number(
        config.invulnerability,
        path .. ".invulnerability",
        false
    )
    if invulnerability == nil then invulnerability = 0.18 end
    if invulnerability < 0 then
        validator:error(
            path .. ".invulnerability",
            "must not be negative"
        )
    elseif invulnerability > duration then
        validator:error(
            path .. ".invulnerability",
            "must not exceed dodge duration"
        )
    end
    local cooldown =
        validator:number(config.cooldown, path .. ".cooldown", false)
    if cooldown and cooldown < 0 then
        validator:error(path .. ".cooldown", "must not be negative")
    end
end

local function dodgeOf(entity)
    return entity and entity.components and
        entity.components["action.dodge"] or nil
end

local input_system = {
    id = "action.dodge.player_input",
    phase = "input",
    order = 30,
}

function input_system:update(world)
    local input = world.host.input
    for _, entity in ipairs(
        world:query(
            "control.player",
            "movement.topdown",
            "action.dodge"
        )
    ) do
        local dodge = dodgeOf(entity)
        local movement = entity.components["movement.topdown"]
        local combat = entity.components["action.combat"]
        if not entity.dead and input:wasPressed(dodge.input) and
           dodge.cooldown_remaining <= 0 and not dodge.active and
           not (combat and combat.active) and
           world:allows(entity, "act") then
            local direction_x, direction_y = util.normalize(
                movement.intent_x,
                movement.intent_y
            )
            if direction_x == 0 and direction_y == 0 then
                direction_x, direction_y =
                    world:service("motion"):facing(entity)
            end

            dodge.active = true
            dodge.remaining = dodge.duration
            dodge.cooldown_remaining = dodge.cooldown
            dodge.velocity_x =
                direction_x * dodge.distance / dodge.duration
            dodge.velocity_y =
                direction_y * dodge.distance / dodge.duration
            world:service("motion"):setFacing(
                entity,
                direction_x,
                direction_y
            )

            if dodge.invulnerability > 0 then
                world:execute({
                    type = "invulnerable",
                    duration = dodge.invulnerability,
                }, {
                    source = entity,
                    target = entity,
                })
            end
            world.events:emit("dodge.started", {
                entity_id = entity.id,
                duration = dodge.duration,
                distance = dodge.distance,
            })
        end
    end
end

local movement_system = {
    id = "action.dodge.integrate",
    phase = "movement",
    order = 20,
}

function movement_system:update(world, dt)
    for _, entity in ipairs(
        world:query(
            "transform",
            "movement.topdown",
            "action.dodge"
        )
    ) do
        local dodge = dodgeOf(entity)
        local movement = entity.components["movement.topdown"]
        dodge.cooldown_remaining =
            util.countdown(dodge.cooldown_remaining, dt)
        if dodge.active then
            local step = math.min(dt, dodge.remaining)
            world:service("motion"):move(
                world,
                entity,
                dodge.velocity_x * step,
                dodge.velocity_y * step
            )
            world:service("motion"):setVelocity(
                entity,
                dodge.velocity_x,
                dodge.velocity_y
            )
            dodge.remaining = util.countdown(dodge.remaining, dt)
            if dodge.remaining == 0 then
                dodge.active = false
                dodge.velocity_x = 0
                dodge.velocity_y = 0
                world:service("motion"):setVelocity(entity, 0, 0)
                world.events:emit("dodge.finished", {
                    entity_id = entity.id,
                })
            end
        end
    end
end

local draw_system = {
    id = "action.dodge.feedback",
    draw_order = 23,
}

function draw_system:draw(world)
    for _, entity in ipairs(
        world:query("transform", "action.dodge")
    ) do
        local dodge = dodgeOf(entity)
        if dodge.active then
            local transform = entity.components.transform
            local body = entity.components.body
            local radius = (body and body.radius or 12) + 8
            love.graphics.setColor(0.2, 0.85, 1, 0.42)
            love.graphics.circle(
                "fill",
                transform.x,
                transform.y,
                radius
            )
            love.graphics.setColor(0.55, 0.95, 1, 0.95)
            love.graphics.printf(
                "DODGE",
                transform.x - 45,
                transform.y - radius - 40,
                90,
                "center"
            )
        end
    end
end

function feature:register(host)
    host:registerComponent("action.dodge", {
        validate = function(config, validator, path, partial)
            validateDodge(config, validator, path, partial, host)
        end,
        create = function(config)
            return {
                input = config.input or "dodge",
                duration = config.duration or 0.22,
                distance = config.distance or 78,
                invulnerability = config.invulnerability or 0.18,
                cooldown = config.cooldown or 0.48,
                active = false,
                remaining = 0,
                cooldown_remaining = 0,
                velocity_x = 0,
                velocity_y = 0,
            }
        end,
    })

    local function gate(entity)
        local dodge = dodgeOf(entity)
        if dodge and dodge.active then return false, "dodging" end
        return true
    end
    host:registerGate("move", "dodge.active", gate)
    host:registerGate("act", "dodge.active", gate)

    host:registerEntityInspector("action.dodge", function(entity)
        local dodge = dodgeOf(entity)
        if not dodge then return end
        return {
            dodge_active = dodge.active,
            dodge_remaining = dodge.remaining,
            dodge_cooldown = dodge.cooldown_remaining,
            dodge_velocity_x = dodge.velocity_x,
            dodge_velocity_y = dodge.velocity_y,
        }
    end)

    host:registerSystem(input_system)
    host:registerSystem(movement_system)
    host:registerSystem(draw_system)
end

return feature

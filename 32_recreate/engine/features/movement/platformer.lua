local util = require "engine.core.util"

local feature = {
    id = "movement.platformer",
    requires = {
        "engine.features.motion",
        "engine.features.control",
    },
}

local function validateMovement(config, validator, path, partial, host)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "speed", "acceleration", "air_acceleration",
            "deceleration", "gravity", "jump_speed",
            "max_fall_speed", "coyote_time", "jump_buffer",
            "left_input", "right_input", "jump_input",
        },
        path
    )
    for _, field in ipairs({
        "speed",
        "acceleration",
        "air_acceleration",
        "deceleration",
        "gravity",
        "jump_speed",
        "max_fall_speed",
    }) do
        validator:positive(
            config[field],
            path .. "." .. field,
            not partial and field == "speed"
        )
    end
    for _, field in ipairs({"coyote_time", "jump_buffer"}) do
        local value = validator:number(
            config[field],
            path .. "." .. field,
            false
        )
        if value and value < 0 then
            validator:error(
                path .. "." .. field,
                "must not be negative"
            )
        end
    end

    local inputs = {
        left_input = config.left_input or "move_left",
        right_input = config.right_input or "move_right",
        jump_input = config.jump_input or "jump",
    }
    for field, action in pairs(inputs) do
        validator:string(config[field], path .. "." .. field, false)
        if not host.input:hasAction(action) then
            validator:error(
                path .. "." .. field,
                "references missing input action '" .. action .. "'"
            )
        end
    end
end

local function validateEntity(_, components, validator, path)
    if components["movement.topdown"] then
        validator:error(
            path,
            "cannot be combined with movement.topdown"
        )
    end
    local body = components.body
    if not body or body.shape ~= "circle" then
        validator:error(path, "requires a circle body component")
    end
end

local function approach(value, target, amount)
    if value < target then return math.min(value + amount, target) end
    if value > target then return math.max(value - amount, target) end
    return value
end

local input_system = {
    id = "movement.platformer.player_control",
    phase = "input",
    order = 0,
}

function input_system:update(world)
    local input = world.host.input
    for _, entity in ipairs(
        world:query("movement.platformer", "control.player")
    ) do
        local movement = entity.components["movement.platformer"]
        if not entity.dead then
            movement.intent_x = input:axis(
                movement.left_input,
                movement.right_input,
                "leftx"
            )
            if input:wasPressed(movement.jump_input) then
                movement.jump_buffer_remaining =
                    movement.jump_buffer
            end
        end
    end
end

local movement_system = {
    id = "movement.platformer.integrate",
    phase = "movement",
    order = 0,
}

function movement_system:update(world, dt)
    local motion = world:service("motion")
    for _, entity in ipairs(
        world:query(
            "transform",
            "motion.kinematics",
            "movement.platformer"
        )
    ) do
        local movement = entity.components["movement.platformer"]
        local kinematics = entity.components["motion.kinematics"]
        movement.jump_buffer_remaining = util.countdown(
            movement.jump_buffer_remaining,
            dt
        )
        movement.coyote_remaining = util.countdown(
            movement.coyote_remaining,
            dt
        )
        if kinematics.grounded then
            movement.coyote_remaining = movement.coyote_time
        end

        local allowed =
            not entity.dead and world:allows(entity, "move")
        local intent_x = allowed and movement.intent_x or 0
        local status = world:service("status")
        local status_multiplier = status and
            status:multiplier(entity, "move_speed") or 1
        local stats = world:service("stats")
        local stat_multiplier = stats and
            stats:value(world, entity, "move_speed") or 1
        local target_x =
            intent_x * movement.speed *
                status_multiplier * stat_multiplier
        local acceleration
        if intent_x == 0 then
            acceleration = movement.deceleration
        elseif kinematics.grounded then
            acceleration = movement.acceleration
        else
            acceleration = movement.air_acceleration
        end
        kinematics.velocity_x = approach(
            kinematics.velocity_x,
            target_x,
            acceleration * dt
        )
        if intent_x ~= 0 then
            motion:setFacing(entity, intent_x, 0)
        end

        if allowed and
           movement.jump_buffer_remaining > 0 and
           movement.coyote_remaining > 0 then
            kinematics.velocity_y = -movement.jump_speed
            kinematics.grounded = false
            movement.jump_buffer_remaining = 0
            movement.coyote_remaining = 0
            world.events:emit("platformer.jumped", {
                entity_id = entity.id,
                velocity_y = kinematics.velocity_y,
            })
        end

        kinematics.velocity_y = math.min(
            movement.max_fall_speed,
            kinematics.velocity_y + movement.gravity * dt
        )

        local desired_x = kinematics.velocity_x * dt
        local moved_x = motion:move(
            world,
            entity,
            desired_x,
            0
        )
        if math.abs(moved_x - desired_x) > 0.0001 then
            kinematics.velocity_x = 0
        end

        local was_grounded = kinematics.grounded
        local desired_y = kinematics.velocity_y * dt
        local _, moved_y = motion:move(
            world,
            entity,
            0,
            desired_y
        )
        local vertical_blocked =
            math.abs(moved_y - desired_y) > 0.0001
        if vertical_blocked then
            kinematics.grounded = desired_y >= 0
            kinematics.velocity_y = 0
        else
            kinematics.grounded = false
        end
        if not was_grounded and kinematics.grounded then
            world.events:emit("platformer.landed", {
                entity_id = entity.id,
            })
        end
        kinematics.moving =
            math.abs(kinematics.velocity_x) > 0.0001 or
            math.abs(kinematics.velocity_y) > 0.0001
        movement.intent_x = 0
    end
end

function feature:register(host)
    host:registerComponent("movement.platformer", {
        requires = {
            "body",
            "motion.facing",
            "motion.kinematics",
        },
        validate = function(config, validator, path, partial)
            validateMovement(config, validator, path, partial, host)
        end,
        validateEntity = validateEntity,
        create = function(config)
            return {
                speed = config.speed or 220,
                acceleration = config.acceleration or 1500,
                air_acceleration = config.air_acceleration or 850,
                deceleration = config.deceleration or 1800,
                gravity = config.gravity or 1500,
                jump_speed = config.jump_speed or 560,
                max_fall_speed = config.max_fall_speed or 900,
                coyote_time = config.coyote_time or 0.1,
                jump_buffer = config.jump_buffer or 0.1,
                left_input = config.left_input or "move_left",
                right_input = config.right_input or "move_right",
                jump_input = config.jump_input or "jump",
                intent_x = 0,
                jump_buffer_remaining = 0,
                coyote_remaining = 0,
            }
        end,
    })
    host:registerEntityInspector(
        "movement.platformer",
        function(entity)
            local movement =
                entity.components["movement.platformer"]
            if not movement then return end
            return {
                platformer_speed = movement.speed,
                platformer_gravity = movement.gravity,
                platformer_jump_speed = movement.jump_speed,
                platformer_intent_x = movement.intent_x,
                platformer_jump_buffer =
                    movement.jump_buffer_remaining,
                platformer_coyote = movement.coyote_remaining,
            }
        end
    )
    host:registerDebugDrawer(
        "movement.platformer",
        function(world, options)
            if not options.labels then return end
            for _, entity in ipairs(
                world:query(
                    "transform",
                    "motion.kinematics",
                    "movement.platformer"
                )
            ) do
                local transform = entity.components.transform
                local kinematics =
                    entity.components["motion.kinematics"]
                love.graphics.setColor(0.3, 1, 0.55, 0.95)
                love.graphics.printf(
                    string.format(
                        "PLATFORMER %s  v(%.0f, %.0f)",
                        kinematics.grounded and "GROUND" or "AIR",
                        kinematics.velocity_x,
                        kinematics.velocity_y
                    ),
                    transform.x - 100,
                    transform.y + 34,
                    200,
                    "center"
                )
            end
        end
    )
    host:registerSystem(input_system)
    host:registerSystem(movement_system)
end

return feature

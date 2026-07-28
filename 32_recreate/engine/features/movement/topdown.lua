local util = require "engine.core.util"

local feature = {
    id = "movement.topdown",
    requires = {
        "engine.features.motion",
        "engine.features.control",
    },
}

local input_fields = {
    up_input = "move_up",
    down_input = "move_down",
    left_input = "move_left",
    right_input = "move_right",
}

local function validateMovement(config, validator, path, partial, host)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {
            "speed",
            "up_input", "down_input", "left_input", "right_input",
        },
        path
    )
    validator:positive(config.speed, path .. ".speed", not partial)
    for name, default_action in pairs(input_fields) do
        local action =
            validator:string(config[name], path .. "." .. name, false) or
            default_action
        if not host.input:hasAction(action) then
            validator:error(
                path .. "." .. name,
                "references missing input action '" .. action .. "'"
            )
        end
    end
end

local player_system = {
    id = "movement.topdown.player_control",
    phase = "input",
    order = 0,
}

function player_system:update(world)
    local input = world.host.input
    for _, entity in ipairs(
        world:query("movement.topdown", "control.player")
    ) do
        if not entity.dead then
            local movement = entity.components["movement.topdown"]
            movement.intent_x = input:axis(
                movement.left_input,
                movement.right_input,
                "leftx"
            )
            movement.intent_y = input:axis(
                movement.up_input,
                movement.down_input,
                "lefty"
            )
        end
    end
end

local movement_system = {
    id = "movement.topdown.integrate",
    phase = "movement",
    order = 0,
}

function movement_system:update(world, dt)
    for _, entity in ipairs(
        world:query("transform", "movement.topdown")
    ) do
        local movement = entity.components["movement.topdown"]
        local motion = world:service("motion")

        if not entity.dead and world:allows(entity, "move") then
            local direction_x, direction_y =
                util.normalize(movement.intent_x, movement.intent_y)
            if direction_x ~= 0 or direction_y ~= 0 then
                motion:setFacing(entity, direction_x, direction_y)
            end

            local status = world:service("status")
            local status_multiplier = status and
                status:multiplier(entity, "move_speed") or 1
            local stats = world:service("stats")
            local stat_multiplier = stats and
                stats:value(world, entity, "move_speed") or 1
            local moved_x, moved_y = motion:move(
                world,
                entity,
                direction_x * movement.speed *
                    status_multiplier * stat_multiplier * dt,
                direction_y * movement.speed *
                    status_multiplier * stat_multiplier * dt
            )
            motion:setVelocity(entity, moved_x / dt, moved_y / dt)
        else
            motion:setVelocity(entity, 0, 0)
        end

        movement.intent_x = 0
        movement.intent_y = 0
    end
end

function feature:register(host)
    host:registerComponent("movement.topdown", {
        requires = {"motion.facing", "motion.kinematics"},
        validate = function(config, validator, path, partial)
            validateMovement(config, validator, path, partial, host)
        end,
        validateEntity = function(_, components, validator, path)
            if components["movement.platformer"] then
                validator:error(
                    path,
                    "cannot be combined with movement.platformer"
                )
            end
        end,
        create = function(config)
            return {
                speed = config.speed or 160,
                intent_x = 0,
                intent_y = 0,
                up_input = config.up_input or "move_up",
                down_input = config.down_input or "move_down",
                left_input = config.left_input or "move_left",
                right_input = config.right_input or "move_right",
            }
        end,
    })

    host:registerEntityInspector("movement.topdown", function(entity)
        local movement = entity.components["movement.topdown"]
        if not movement then return end
        return {
            movement_speed = movement.speed,
            movement_intent_x = movement.intent_x,
            movement_intent_y = movement.intent_y,
        }
    end)

    host:registerSystem(player_system)
    host:registerSystem(movement_system)
end

return feature

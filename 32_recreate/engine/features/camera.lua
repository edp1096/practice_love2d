local util = require "engine.core.util"

local feature = {
    id = "camera",
    requires = {"engine.features.world"},
}

local function validateCamera(config, validator, path)
    if config == nil then return end
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {"viewport_width", "viewport_height", "follow_tag"},
        path
    )
    validator:positive(
        config.viewport_width,
        path .. ".viewport_width",
        true
    )
    validator:positive(
        config.viewport_height,
        path .. ".viewport_height",
        true
    )
    validator:string(config.follow_tag, path .. ".follow_tag", false)
end

local camera = {}

local function stateOf(world)
    return world.feature_state.camera
end

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and
        value ~= math.huge and value ~= -math.huge
end

local function centeredAxis(position, viewport_size, stage_size)
    if stage_size <= viewport_size then
        return (stage_size - viewport_size) / 2
    end
    return util.clamp(
        position - viewport_size / 2,
        0,
        stage_size - viewport_size
    )
end

local function boundedAxis(position, viewport_size, stage_size)
    if stage_size <= viewport_size then
        return (stage_size - viewport_size) / 2
    end
    return util.clamp(position, 0, stage_size - viewport_size)
end

function camera:snap(world)
    local state = stateOf(world)
    if not state then return end
    local target = world:findByTag(state.follow_tag)[1]
    local transform = target and target.components.transform
    local target_x = transform and transform.x or world.stage.width / 2
    local target_y = transform and transform.y or world.stage.height / 2
    state.x = centeredAxis(
        target_x,
        state.width,
        world.stage.width
    )
    state.y = centeredAxis(
        target_y,
        state.height,
        world.stage.height
    )
    state.target_id = target and target.id or nil
end

function camera:shake(world, options)
    local state = stateOf(world)
    if not state then
        return {
            applied = false,
            reason = "camera_unavailable",
        }
    end
    options = options or {}
    local duration = options.duration or 0.12
    local magnitude = options.magnitude or 4
    local frequency = options.frequency or 30
    if not isFiniteNumber(duration) or
       not isFiniteNumber(magnitude) or
       not isFiniteNumber(frequency) then
        return nil, "camera shake values must be finite numbers"
    end
    if frequency <= 0 then
        return nil, "camera shake frequency must be greater than zero"
    end
    if duration <= 0 or magnitude <= 0 then
        return {
            applied = false,
            reason = "zero_intensity",
        }
    end

    local shake = state.shake
    shake.sequence = shake.sequence + 1
    shake.duration = duration
    shake.remaining = duration
    shake.elapsed = 0
    shake.magnitude = magnitude
    shake.frequency = frequency
    shake.phase = (shake.sequence * 2.3999632297287) %
        (math.pi * 2)
    shake.offset_x =
        math.sin(shake.phase) * shake.magnitude
    shake.offset_y =
        math.cos(shake.phase * 1.37) * shake.magnitude * 0.65

    world.events:emit("camera.shake_started", {
        duration = duration,
        magnitude = magnitude,
        frequency = frequency,
        sequence = shake.sequence,
        reason = options.reason,
    })
    return {
        applied = true,
        duration = duration,
        magnitude = magnitude,
        frequency = frequency,
        sequence = shake.sequence,
    }
end

function camera:view(world)
    local state = stateOf(world)
    if not state then
        return {
            x = 0,
            y = 0,
            width = world.stage.width,
            height = world.stage.height,
        }
    end
    local x = boundedAxis(
        state.x + state.shake.offset_x,
        state.width,
        world.stage.width
    )
    local y = boundedAxis(
        state.y + state.shake.offset_y,
        state.height,
        world.stage.height
    )
    return {
        x = x,
        y = y,
        width = state.width,
        height = state.height,
        target_id = state.target_id,
        shake_remaining = state.shake.remaining,
        shake_magnitude = state.shake.magnitude,
        shake_offset_x = x - state.x,
        shake_offset_y = y - state.y,
        shake_raw_offset_x = state.shake.offset_x,
        shake_raw_offset_y = state.shake.offset_y,
        shake_sequence = state.shake.sequence,
    }
end

local camera_system = {
    id = "camera.follow",
    phase = "presentation",
    order = 100,
}

function camera_system:updateUnscaled(world, raw_dt)
    local state = stateOf(world)
    local shake = state and state.shake
    if not shake or shake.remaining <= 0 then return end

    shake.elapsed = shake.elapsed + raw_dt
    shake.remaining = util.countdown(shake.remaining, raw_dt)
    if shake.remaining <= 0 then
        shake.remaining = 0
        shake.offset_x = 0
        shake.offset_y = 0
        shake.duration = 0
        shake.elapsed = 0
        shake.magnitude = 0
        shake.frequency = 0
        shake.phase = 0
        world.events:emit("camera.shake_finished", {
            sequence = shake.sequence,
        })
        return
    end

    local envelope = shake.remaining / shake.duration
    local angle = shake.phase +
        shake.elapsed * shake.frequency * math.pi * 2
    shake.offset_x =
        math.sin(angle) * shake.magnitude * envelope
    shake.offset_y =
        math.cos(angle * 1.37) * shake.magnitude * 0.65 * envelope
end

function camera_system:update(world)
    camera:snap(world)
end

function feature:register(host)
    host:registerService("camera", camera)
    host.rules:registerAction("camera_shake", {
        validate = function(action, validator, path)
            validator:keys(
                action,
                {"type", "duration", "magnitude", "frequency"},
                path
            )
            local duration = validator:positive(
                action.duration,
                path .. ".duration",
                true
            )
            local magnitude = validator:positive(
                action.magnitude,
                path .. ".magnitude",
                true
            )
            local frequency = validator:positive(
                action.frequency,
                path .. ".frequency",
                false
            )
            if duration and duration > 1 then
                validator:error(
                    path .. ".duration",
                    "must not exceed 1 second"
                )
            end
            if magnitude and magnitude > 64 then
                validator:error(
                    path .. ".magnitude",
                    "must not exceed 64 pixels"
                )
            end
            if frequency and frequency > 120 then
                validator:error(
                    path .. ".frequency",
                    "must not exceed 120 Hz"
                )
            end
        end,
        execute = function(action, context)
            return camera:shake(context.world, {
                duration = action.duration,
                magnitude = action.magnitude,
                frequency = action.frequency,
                reason = "action",
            })
        end,
    })
    host:registerStageSection("camera", {
        priority = 90,
        validate = validateCamera,
        load = function(world, config, stage)
            config = config or {}
            world.feature_state.camera = {
                x = 0,
                y = 0,
                width = config.viewport_width or stage.width,
                height = config.viewport_height or stage.height,
                follow_tag = config.follow_tag or "player",
                target_id = nil,
                shake = {
                    duration = 0,
                    remaining = 0,
                    elapsed = 0,
                    magnitude = 0,
                    frequency = 0,
                    phase = 0,
                    offset_x = 0,
                    offset_y = 0,
                    sequence = 0,
                },
            }
            camera:snap(world)
            return true
        end,
    })
    host:registerWorldInspector("camera", function(world)
        return {camera = camera:view(world)}
    end)
    host:registerSystem(camera_system)
end

return feature

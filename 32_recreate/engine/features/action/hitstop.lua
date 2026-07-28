local util = require "engine.core.util"

local feature = {
    id = "action.hitstop",
    requires = {"engine.features.world"},
}

local state_key = "action.hitstop"

local function stateOf(world)
    local state = world.feature_state[state_key]
    if not state then
        state = {remaining = 0}
        world.feature_state[state_key] = state
    end
    return state
end

local function validateAction(action, validator, path)
    validator:keys(action, {"type", "duration"}, path)
    local duration =
        validator:positive(action.duration, path .. ".duration", true)
    if duration and duration > 0.25 then
        validator:error(path .. ".duration", "must not exceed 0.25 seconds")
    end
end

function feature:register(host)
    host.rules:registerAction("hitstop", {
        validate = validateAction,
        execute = function(action, context)
            local state = stateOf(context.world)
            state.remaining = math.max(state.remaining, action.duration)
            context.events:emit("hitstop.started", {
                duration = action.duration,
                source_id =
                    context.source and context.source.id or nil,
                target_id =
                    context.target and context.target.id or nil,
            })
            return {
                applied = true,
                duration = action.duration,
            }
        end,
    })

    host:registerTimeFilter(
        "action.hitstop",
        10,
        function(world, dt, raw_dt)
            local state = stateOf(world)
            if state.remaining <= 0 then return dt end
            state.remaining = util.countdown(state.remaining, raw_dt)
            if state.remaining == 0 then
                world.events:emit("hitstop.finished")
            end
            return 0
        end
    )

    host:registerWorldInspector("action.hitstop", function(world)
        return {
            hitstop_remaining = stateOf(world).remaining,
        }
    end)
end

return feature

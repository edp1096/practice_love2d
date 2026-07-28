local util = require "engine.core.util"
local Schema = require "engine.runtime.session_schema"

local feature = {
    id = "rpg.flags",
    requires = {"engine.features.session"},
}

local function validateName(value, validator, path)
    return validator:string(value, path, true)
end

function feature:register(host)
    local session = host.services.session
    local state = session:registerSection("rpg.flags", {
        version = 1,
        defaults = {values = {}},
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "rpg.flags",
                {"values"},
                {"values"}
            )
            if not valid then return nil, value_error end
            return Schema.map(
                value.values,
                "rpg.flags.values",
                function(flag, path)
                    if flag ~= true then
                        return nil, path .. " must be true"
                    end
                    return true
                end
            )
        end,
    })
    local flags = {}

    function flags:get(name)
        return state.values[name] == true
    end

    function flags:set(world, name, value)
        value = value ~= false
        local previous = self:get(name)
        state.values[name] = value or nil
        if previous ~= value and world then
            world.events:emit("flag.changed", {
                name = name,
                value = value,
                previous = previous,
            })
        end
        return {
            applied = previous ~= value,
            name = name,
            value = value,
            previous = previous,
        }
    end

    host.rules:registerAction("set_flag", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "name", "value"}, path)
            validateName(action.name, validator, path .. ".name")
            validator:boolean(action.value, path .. ".value", false)
        end,
        execute = function(action, context)
            return flags:set(
                context.world,
                action.name,
                action.value ~= false
            )
        end,
    })
    host.rules:registerAction("clear_flag", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "name"}, path)
            validateName(action.name, validator, path .. ".name")
        end,
        execute = function(action, context)
            return flags:set(context.world, action.name, false)
        end,
    })
    host.rules:registerCondition("flag", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "name", "value"}, path)
            validateName(condition.name, validator, path .. ".name")
            validator:boolean(
                condition.value,
                path .. ".value",
                false
            )
        end,
        evaluate = function(condition)
            return flags:get(condition.name) ==
                (condition.value ~= false)
        end,
    })

    host:registerService("flags", flags)
    host:registerWorldInspector("rpg.flags", function()
        return {
            flags = util.deepCopy(state.values),
            flag_count = #util.sortedKeys(state.values),
        }
    end)
end

return feature

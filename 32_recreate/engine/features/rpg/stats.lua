local util = require "engine.core.util"

local feature = {
    id = "rpg.stats",
    requires = {"engine.features.action.health"},
}

local stat_names = {
    "attack",
    "defense",
    "move_speed",
}

local stat_defaults = {
    attack = 0,
    defense = 0,
    move_speed = 1,
}

local stat_set = {}
for _, name in ipairs(stat_names) do stat_set[name] = true end

local function validateStatValue(
    name,
    value,
    validator,
    path,
    required
)
    value = validator:number(value, path, required)
    if value and value < 0 then
        validator:error(path, "must not be negative")
        return nil
    end
    if name == "move_speed" and value == 0 then
        validator:error(path, "must be greater than zero")
        return nil
    end
    return value
end

function feature:register(host)
    local providers = {}
    local stats = {}

    function stats:registerProvider(name, handler)
        assert(
            type(name) == "string" and name ~= "",
            "stat provider name is required"
        )
        assert(type(handler) == "function", "stat provider is required")
        for _, provider in ipairs(providers) do
            assert(
                provider.name ~= name,
                "duplicate stat provider: " .. name
            )
        end
        providers[#providers + 1] = {
            name = name,
            handler = handler,
        }
        table.sort(providers, function(left, right)
            return left.name < right.name
        end)
    end

    function stats:validateModifiers(modifiers, validator, path)
        modifiers = validator:table(modifiers, path, true)
        if not modifiers then return end
        validator:keys(modifiers, stat_names, path)
        for name, value in pairs(modifiers) do
            if stat_set[name] then
                value = validator:number(
                    value,
                    path .. "." .. name,
                    true
                )
                if value and name ~= "move_speed" and
                   value % 1 ~= 0 then
                    validator:error(
                        path .. "." .. name,
                        "must be an integer"
                    )
                end
            end
        end
    end

    function stats:value(world, entity, name)
        assert(stat_set[name], "unknown stat: " .. tostring(name))
        local component = entity and entity.components and
            entity.components["rpg.stats"] or nil
        local value = component and component[name] or stat_defaults[name]
        for _, provider in ipairs(providers) do
            value = value +
                (provider.handler(world, entity, name) or 0)
        end
        return math.max(0, value)
    end

    function stats:all(world, entity)
        local result = {}
        for _, name in ipairs(stat_names) do
            result[name] = self:value(world, entity, name)
        end
        return result
    end

    host:registerComponent("rpg.stats", {
        validate = function(config, validator, path)
            if not validator:table(config, path, true) then return end
            validator:keys(config, stat_names, path)
            for _, name in ipairs(stat_names) do
                validateStatValue(
                    name,
                    config[name],
                    validator,
                    path .. "." .. name,
                    false
                )
            end
        end,
        create = function(config)
            return util.merge(stat_defaults, config)
        end,
    })

    host.rules:registerActionInterceptor(
        "damage",
        "rpg.stats.damage",
        1,
        function(action, context, nextHandler)
            if context.damage_kind == "periodic" then
                return nextHandler()
            end
            local attack = stats:value(
                context.world,
                context.source,
                "attack"
            )
            local defense = stats:value(
                context.world,
                context.target,
                "defense"
            )
            local adjusted = math.max(
                1,
                action.amount + attack - defense
            )
            return nextHandler({
                type = action.type,
                amount = adjusted,
            })
        end
    )

    host:registerService("stats", stats)
    host:registerEntityInspector("rpg.stats", function(entity, world)
        if not entity.components["rpg.stats"] and
           not entity.components["rpg.equipment"] then
            return
        end
        return {
            stats = stats:all(world, entity),
        }
    end)
end

return feature

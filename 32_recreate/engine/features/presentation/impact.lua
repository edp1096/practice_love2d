local util = require "engine.core.util"

local feature = {
    id = "presentation.impact",
    requires = {
        "engine.features.camera",
    },
}

local defaults = {
    damage = {
        duration = 0.09,
        magnitude = 2.5,
        frequency = 34,
    },
    kill = {
        duration = 0.16,
        magnitude = 5,
        frequency = 30,
    },
    parry = {
        duration = 0.14,
        magnitude = 6,
        frequency = 36,
    },
    perfect_parry = {
        duration = 0.2,
        magnitude = 10,
        frequency = 40,
    },
}

local effect_names = {
    "damage",
    "kill",
    "parry",
    "perfect_parry",
}

local function validateEffect(value, validator, path)
    if value == nil then return end
    if not validator:table(value, path, true) then return end
    validator:keys(
        value,
        {"duration", "magnitude", "frequency"},
        path
    )
    local duration = validator:positive(
        value.duration,
        path .. ".duration",
        false
    )
    local magnitude = validator:positive(
        value.magnitude,
        path .. ".magnitude",
        false
    )
    local frequency = validator:positive(
        value.frequency,
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
end

local function validateConfig(config)
    if config == nil then return true end
    if type(config) ~= "table" then
        return nil, "game manifest impact_feedback must be a table"
    end
    local allowed = {enabled = true}
    for _, name in ipairs(effect_names) do allowed[name] = true end
    local errors = {}
    for _, key in ipairs(util.sortedKeys(config)) do
        if not allowed[key] then
            errors[#errors + 1] =
                "game manifest impact_feedback contains unknown field '" ..
                tostring(key) .. "'"
        end
    end
    if config.enabled ~= nil and type(config.enabled) ~= "boolean" then
        errors[#errors + 1] =
            "game manifest impact_feedback.enabled must be a boolean"
    end

    local validator = {
        table = function(_, value, path)
            if type(value) ~= "table" then
                errors[#errors + 1] = path .. " must be a table"
                return nil
            end
            return value
        end,
        keys = function(_, value, names, path)
            local fields = {}
            for _, name in ipairs(names) do fields[name] = true end
            for _, key in ipairs(util.sortedKeys(value)) do
                if not fields[key] then
                    errors[#errors + 1] = path ..
                        " contains unknown field '" .. tostring(key) .. "'"
                end
            end
        end,
        positive = function(_, value, path)
            if value == nil then return nil end
            if type(value) ~= "number" or value ~= value or
               value == math.huge or value == -math.huge then
                errors[#errors + 1] = path ..
                    " must be a finite positive number"
                return nil
            end
            if value <= 0 then
                errors[#errors + 1] = path ..
                    " must be a positive number"
                return nil
            end
            return value
        end,
        error = function(_, path, message)
            errors[#errors + 1] = path .. " " .. message
        end,
    }
    for _, name in ipairs(effect_names) do
        validateEffect(
            config[name],
            validator,
            "game manifest impact_feedback." .. name
        )
    end
    if #errors > 0 then return nil, table.concat(errors, "; ") end
    return true
end

function feature:register(host)
    local raw_config = host.manifest.impact_feedback
    local config = type(raw_config) == "table" and raw_config or {}
    local effects = {}
    for _, name in ipairs(effect_names) do
        local override =
            type(config[name]) == "table" and config[name] or {}
        effects[name] = util.merge(defaults[name], override)
    end
    local enabled = config.enabled ~= false
    local camera = host.services.camera

    local function playerParticipates(world, payload)
        for _, field in ipairs({"source_id", "target_id"}) do
            local entity = payload[field] and world:get(payload[field])
            if entity and entity.tag_set.player then return true end
        end
        return false
    end

    local function play(world, name)
        local effect = effects[name]
        camera:shake(world, {
            duration = effect.duration,
            magnitude = effect.magnitude,
            frequency = effect.frequency,
            reason = name,
        })
    end

    host:registerBootValidator("presentation.impact", function()
        return validateConfig(host.manifest.impact_feedback)
    end)
    host:registerWorldInitializer(
        "presentation.impact",
        80,
        function(world)
            if not enabled then return true end
            world.events:on("actor.damaged", function(payload)
                if payload.debug or payload.damage_kind == "periodic" or
                   not playerParticipates(world, payload) then
                    return
                end
                play(world, "damage")
            end)
            world.events:on("actor.killed", function(payload)
                if payload.debug or
                   not playerParticipates(world, payload) then
                    return
                end
                play(world, "kill")
            end)
            world.events:on("attack.parried", function(payload)
                if not playerParticipates(world, payload) then return end
                play(
                    world,
                    payload.perfect and "perfect_parry" or "parry"
                )
            end)
            return true
        end
    )
end

return feature

local util = require "engine.core.util"

local feature = {
    id = "action.behavior_ai",
    requires = {
        "engine.features.movement.topdown",
        "engine.features.action.combat",
        "engine.features.action.health",
    },
}

local function nonNegative(value, validator, path, required)
    value = validator:number(value, path, required)
    if value and value < 0 then
        validator:error(path, "must not be negative")
    end
    return value
end

local function validateMovement(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(
        config,
        {"minimum_range", "preferred_range", "orbit"},
        path
    )
    local minimum = nonNegative(
        config.minimum_range,
        validator,
        path .. ".minimum_range",
        false
    ) or 0
    local preferred = nonNegative(
        config.preferred_range,
        validator,
        path .. ".preferred_range",
        true
    )
    if preferred and minimum > preferred then
        validator:error(
            path .. ".minimum_range",
            "must not exceed preferred_range"
        )
    end
    validator:boolean(config.orbit, path .. ".orbit", false)
end

local function validateAttack(attack, validator, path)
    if not validator:table(attack, path, true) then return end
    validator:keys(
        attack,
        {"ability", "minimum_range", "maximum_range"},
        path
    )
    validator:reference(attack.ability, "ability", path .. ".ability")
    local minimum = nonNegative(
        attack.minimum_range,
        validator,
        path .. ".minimum_range",
        false
    ) or 0
    local maximum = validator:positive(
        attack.maximum_range,
        path .. ".maximum_range",
        true
    )
    if maximum and minimum > maximum then
        validator:error(
            path .. ".minimum_range",
            "must not exceed maximum_range"
        )
    end
end

local function validateAI(config, validator, path, partial)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"target_tag", "aggro_range", "patterns"}, path)
    validator:string(config.target_tag, path .. ".target_tag", not partial)
    local aggro = validator:positive(
        config.aggro_range,
        path .. ".aggro_range",
        not partial
    )
    local patterns = validator:array(
        config.patterns,
        path .. ".patterns",
        not partial
    )
    if patterns and #patterns == 0 then
        validator:error(path .. ".patterns", "must not be empty")
    end
    local seen = {}
    local previous_threshold = 1
    for index, pattern in ipairs(patterns or {}) do
        local pattern_path = string.format("%s.patterns[%d]", path, index)
        if validator:table(pattern, pattern_path, true) then
            validator:keys(
                pattern,
                {
                    "id", "health_ratio_at_most",
                    "movement", "attacks",
                },
                pattern_path
            )
            local id = validator:string(
                pattern.id,
                pattern_path .. ".id",
                true
            )
            if id and seen[id] then
                validator:error(
                    pattern_path .. ".id",
                    "duplicates another AI pattern id"
                )
            elseif id then
                seen[id] = true
            end
            local threshold = validator:number(
                pattern.health_ratio_at_most,
                pattern_path .. ".health_ratio_at_most",
                index > 1
            )
            if index == 1 and threshold ~= nil then
                validator:error(
                    pattern_path .. ".health_ratio_at_most",
                    "the first pattern is the unconditional fallback"
                )
            elseif threshold and
                   (threshold <= 0 or threshold >= previous_threshold) then
                validator:error(
                    pattern_path .. ".health_ratio_at_most",
                    "must be greater than zero and lower than the previous threshold"
                )
            elseif threshold then
                previous_threshold = threshold
            end
            validateMovement(
                pattern.movement,
                validator,
                pattern_path .. ".movement"
            )
            local attacks = validator:array(
                pattern.attacks,
                pattern_path .. ".attacks",
                true
            )
            if attacks and #attacks == 0 then
                validator:error(
                    pattern_path .. ".attacks",
                    "must not be empty"
                )
            end
            for attack_index, attack in ipairs(attacks or {}) do
                validateAttack(
                    attack,
                    validator,
                    string.format(
                        "%s.attacks[%d]",
                        pattern_path,
                        attack_index
                    )
                )
                if aggro and attack.maximum_range and
                   attack.maximum_range > aggro then
                    validator:error(
                        string.format(
                            "%s.attacks[%d].maximum_range",
                            pattern_path,
                            attack_index
                        ),
                        "must not exceed aggro_range"
                    )
                end
            end
            if aggro and pattern.movement and
               pattern.movement.preferred_range and
               pattern.movement.preferred_range > aggro then
                validator:error(
                    pattern_path .. ".movement.preferred_range",
                    "must not exceed aggro_range"
                )
            end
        end
    end
end

local function validateAIEntity(config, components, validator, path)
    local combat = components["action.combat"]
    if not combat then
        validator:error(path, "requires component 'action.combat'")
        return
    end
    local abilities = {}
    for _, ability in ipairs(combat.abilities or {}) do
        abilities[ability] = true
    end
    for pattern_index, pattern in ipairs(config.patterns or {}) do
        for attack_index, attack in ipairs(pattern.attacks or {}) do
            if attack.ability and not abilities[attack.ability] then
                validator:error(
                    string.format(
                        "%s.patterns[%d].attacks[%d].ability",
                        path,
                        pattern_index,
                        attack_index
                    ),
                    "must also appear in action.combat.abilities"
                )
            end
        end
    end
end

local function nearestTarget(world, source, tag, maximum_distance)
    local source_transform = source.components.transform
    local nearest = nil
    local nearest_distance = maximum_distance
    for _, candidate in ipairs(world:findByTag(tag)) do
        local transform = candidate.components.transform
        if transform and not candidate.dead and candidate ~= source then
            local distance = util.length(
                transform.x - source_transform.x,
                transform.y - source_transform.y
            )
            if distance < nearest_distance then
                nearest = candidate
                nearest_distance = distance
            end
        end
    end
    return nearest, nearest_distance
end

local function activePattern(entity, ai)
    local health = entity.components["action.health"]
    local ratio = health.current / health.max
    local selected = ai.patterns[1]
    for index = 2, #ai.patterns do
        local candidate = ai.patterns[index]
        if ratio <= candidate.health_ratio_at_most then
            selected = candidate
        end
    end
    if ai.active_pattern ~= selected.id then
        local previous = ai.active_pattern
        ai.active_pattern = selected.id
        ai.attack_index = 1
        return selected, previous
    end
    return selected
end

local function attackInRange(attack, distance)
    return distance >= (attack.minimum_range or 0) and
        distance <= attack.maximum_range
end

local function requestAttack(entity, ai, pattern, distance)
    local combat = entity.components["action.combat"]
    if combat.active or combat.cooldown > 0 then return end
    local count = #pattern.attacks
    for offset = 0, count - 1 do
        local index = ((ai.attack_index + offset - 1) % count) + 1
        local attack = pattern.attacks[index]
        if attackInRange(attack, distance) then
            entity.commands.ability = attack.ability
            ai.attack_index = (index % count) + 1
            return
        end
    end
end

local function updateMovement(entity, ai, pattern, dx, dy, distance)
    local movement = entity.components["movement.topdown"]
    local authored = pattern.movement
    local x, y = util.normalize(dx, dy)
    if distance > authored.preferred_range then
        movement.intent_x, movement.intent_y = x, y
    elseif distance < (authored.minimum_range or 0) then
        movement.intent_x, movement.intent_y = -x, -y
    elseif authored.orbit and distance > 0 then
        movement.intent_x = -y * ai.orbit_direction
        movement.intent_y = x * ai.orbit_direction
    end
end

local ai_system = {
    id = "action.behavior_ai.intent",
    phase = "intent",
    order = 0,
}

function ai_system:update(world)
    for _, entity in ipairs(
        world:query(
            "transform",
            "movement.topdown",
            "action.combat",
            "action.health",
            "action.behavior_ai"
        )
    ) do
        if not entity.dead then
            local ai = entity.components["action.behavior_ai"]
            local pattern, previous = activePattern(entity, ai)
            if previous ~= nil then
                world.events:emit("ai.pattern_changed", {
                    entity_id = entity.id,
                    previous_pattern = previous,
                    pattern_id = pattern.id,
                })
            end
            local target, distance = nearestTarget(
                world,
                entity,
                ai.target_tag,
                ai.aggro_range
            )
            if target then
                local source_transform = entity.components.transform
                local target_transform = target.components.transform
                local dx = target_transform.x - source_transform.x
                local dy = target_transform.y - source_transform.y
                world:service("motion"):setFacing(entity, dx, dy)
                updateMovement(entity, ai, pattern, dx, dy, distance)
                requestAttack(entity, ai, pattern, distance)
            end
        end
    end
end

local function stableDirection(id)
    local value = 0
    for index = 1, #id do
        value = (value + string.byte(id, index)) % 2
    end
    return value == 0 and 1 or -1
end

function feature:register(host)
    host:registerComponent("action.behavior_ai", {
        requires = {
            "movement.topdown",
            "action.combat",
            "action.health",
        },
        validate = validateAI,
        validateEntity = validateAIEntity,
        create = function(config, entity)
            return {
                target_tag = config.target_tag or "player",
                aggro_range = config.aggro_range or 320,
                patterns = util.deepCopy(config.patterns),
                active_pattern = nil,
                attack_index = 1,
                orbit_direction = stableDirection(entity.id),
            }
        end,
    })
    host:registerEntityInspector("action.behavior_ai", function(entity)
        local ai = entity.components["action.behavior_ai"]
        if not ai then return end
        return {
            ai_target_tag = ai.target_tag,
            ai_aggro_range = ai.aggro_range,
            ai_pattern = ai.active_pattern,
            ai_attack_index = ai.attack_index,
        }
    end)
    host:registerSystem(ai_system)
end

return feature

local util = require "engine.core.util"

local feature = {
    id = "action.combat",
    requires = {
        "engine.features.world",
        "engine.features.control",
        "engine.features.action.health",
        "engine.features.action.hitbox",
    },
}

local function validateActions(actions, validator, host, path, required)
    actions = validator:array(actions, path, required)
    if actions and #actions == 0 then
        validator:error(path, "must contain at least one action")
    end
    for index, action in ipairs(actions or {}) do
        host.rules:validateAction(
            action,
            validator,
            string.format("%s[%d]", path, index)
        )
    end
    return actions
end

local function validateAbility(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "hitbox",
            "cooldown", "windup", "duration",
            "recovery", "lock_movement", "effects",
            "activation", "visual",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    local hitbox = validator:table(definition.hitbox, "hitbox", false)
    if hitbox then
        host.services["action.hitbox"]:validate(
            hitbox,
            validator,
            "hitbox"
        )
    end

    local cooldown = validator:number(
        definition.cooldown,
        "cooldown",
        true
    )
    if cooldown and cooldown < 0 then
        validator:error("cooldown", "must not be negative")
    end

    local duration = validator:positive(
        definition.duration,
        "duration",
        true
    )

    local windup = validator:number(
        definition.windup,
        "windup",
        false
    )
    if windup and windup < 0 then
        validator:error("windup", "must not be negative")
    end

    local recovery = validator:number(
        definition.recovery,
        "recovery",
        false
    )
    if recovery and recovery < 0 then
        validator:error("recovery", "must not be negative")
    end
    validator:boolean(
        definition.lock_movement,
        "lock_movement",
        false
    )

    local effects = validateActions(
        definition.effects,
        validator,
        host,
        "effects",
        hitbox ~= nil
    )
    if effects and not hitbox then
        validator:error("effects", "requires a hitbox")
    end
    local activation = validateActions(
        definition.activation,
        validator,
        host,
        "activation",
        false
    )
    if not hitbox and not activation then
        validator:error(
            "content",
            "ability requires a hitbox or activation actions"
        )
    end

    local visual = validator:table(definition.visual, "visual", false)
    if visual then
        validator:keys(
            visual,
            {"asset", "scale", "distance", "rotation_offset"},
            "visual"
        )
        validator:reference(visual.asset, "asset", "visual.asset")
        validator:positive(visual.scale, "visual.scale", false)
        validator:number(visual.distance, "visual.distance", false)
        validator:number(
            visual.rotation_offset,
            "visual.rotation_offset",
            false
        )
    end
end

local function validateCombatInput(config, validator, path, _, host)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"attack", "bindings"}, path)
    local action =
        validator:string(config.attack, path .. ".attack", false) or "attack"
    if config.bindings == nil and not host.input:hasAction(action) then
        validator:error(
            path .. ".attack",
            "references missing input action '" .. action .. "'"
        )
    end

    local bindings =
        validator:array(config.bindings, path .. ".bindings", false)
    if bindings and config.attack ~= nil then
        validator:error(path, "must use either attack or bindings, not both")
    end
    if bindings and #bindings == 0 then
        validator:error(path .. ".bindings", "must not be empty")
    end
    local seen_inputs = {}
    for index, binding in ipairs(bindings or {}) do
        local binding_path =
            string.format("%s.bindings[%d]", path, index)
        if validator:table(binding, binding_path, true) then
            validator:keys(binding, {"input", "ability"}, binding_path)
            local input = validator:string(
                binding.input,
                binding_path .. ".input",
                true
            )
            if input and not host.input:hasAction(input) then
                validator:error(
                    binding_path .. ".input",
                    "references missing input action '" .. input .. "'"
                )
            elseif input and seen_inputs[input] then
                validator:error(
                    binding_path .. ".input",
                    "duplicates another input binding"
                )
            elseif input then
                seen_inputs[input] = true
            end
            validator:reference(
                binding.ability,
                "ability",
                binding_path .. ".ability"
            )
        end
    end
end

local function validateCombat(config, validator, path, partial)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"team", "abilities", "primary"}, path)
    validator:string(config.team, path .. ".team", not partial)
    local abilities =
        validator:array(config.abilities, path .. ".abilities", not partial)
    local seen = {}
    for index, ability_id in ipairs(abilities or {}) do
        validator:reference(
            ability_id,
            "ability",
            string.format("%s.abilities[%d]", path, index)
        )
        if seen[ability_id] then
            validator:error(
                string.format("%s.abilities[%d]", path, index),
                "duplicates another ability"
            )
        end
        seen[ability_id] = true
    end
    if config.primary then
        validator:reference(config.primary, "ability", path .. ".primary")
        if abilities and not seen[config.primary] then
            validator:error(
                path .. ".primary",
                "must also appear in abilities"
            )
        end
    end
end

local function validateCombatInputEntity(
    config,
    components,
    validator,
    path
)
    local combat = components["action.combat"]
    if not combat then
        validator:error(path, "requires component 'action.combat'")
        return
    end
    local available = {}
    for _, ability_id in ipairs(combat.abilities or {}) do
        available[ability_id] = true
    end
    for index, binding in ipairs(config.bindings or {}) do
        if binding.ability and not available[binding.ability] then
            validator:error(
                string.format("%s.bindings[%d].ability", path, index),
                "must also appear in action.combat.abilities"
            )
        end
    end
end

local function targetIsInside(world, source, target, ability)
    return world:service("action.hitbox"):contains(
        source,
        target,
        ability.hitbox
    )
end

local function targetCanBeHit(active, target_id, hitbox)
    local record = active.hit_targets[target_id]
    if not record then return true end
    return record.count < (hitbox.max_hits or 1) and
        record.repeat_remaining <= 0
end

local function recordHit(active, target_id, hitbox)
    local record = active.hit_targets[target_id]
    if not record then
        record = {
            count = 0,
            repeat_remaining = 0,
        }
        active.hit_targets[target_id] = record
    end
    record.count = record.count + 1
    record.repeat_remaining = hitbox.repeat_interval or math.huge
    active.hit_count = active.hit_count + 1
    return record.count
end

local function updateHitTimers(active, dt)
    for _, record in pairs(active.hit_targets or {}) do
        if record.repeat_remaining ~= math.huge then
            record.repeat_remaining =
                util.countdown(record.repeat_remaining, dt)
        end
    end
end

local function finishAbility(world, source, combat, ability)
    if (ability.recovery or 0) > 0 then
        combat.active.phase = "recovery"
        combat.active.remaining = ability.recovery
        world.events:emit("ability.recovery_started", {
            source_id = source.id,
            ability_id = ability.id,
            recovery = ability.recovery,
        })
    else
        combat.active = nil
        world.events:emit("ability.finished", {
            source_id = source.id,
            ability_id = ability.id,
        })
    end
end

local function applyAbilityHits(world, source, combat, ability)
    if not ability.hitbox then return end
    for _, target in ipairs(
        world:query(
            "transform",
            "action.hurtbox",
            "action.health",
            "action.combat"
        )
    ) do
        if not world:allows(source, "act") then break end
        local target_combat = target.components["action.combat"]
        if target ~= source and not target.dead and
           target_combat.team ~= combat.team and
           targetCanBeHit(
               combat.active,
               target.id,
               ability.hitbox
           ) and
           targetIsInside(world, source, target, ability) then
            local action_failure
            local hit_result, hit_error = world:transaction(function()
                local target_hit_index = recordHit(
                    combat.active,
                    target.id,
                    ability.hitbox
                )
                local effects, effect_error, failure =
                    world:executeActions(ability.effects, {
                        source = source,
                        target = target,
                        ability = ability,
                    })
                if not effects then
                    action_failure = failure
                    return nil, effect_error
                end
                local applied = false
                for _, result in ipairs(effects.results) do
                    if type(result) == "table" and result.applied then
                        applied = true
                    end
                end
                world.events:emit("ability.hit", {
                    source_id = source.id,
                    target_id = target.id,
                    ability_id = ability.id,
                    target_hit_index = target_hit_index,
                    hit_index = combat.active.hit_count,
                    applied = applied,
                })
                return {applied = true}
            end)
            if not hit_result then
                world.events:emit("ability.action_failed", {
                    source_id = source.id,
                    target_id = target.id,
                    ability_id = ability.id,
                    scope = "hit",
                    action_index =
                        action_failure and action_failure.index or nil,
                    action_type = action_failure and
                        action_failure.action.type or nil,
                    error = hit_error,
                })
                return nil, hit_error
            end
        end
    end
    return true
end

local function applyActivation(world, source, ability)
    local result, action_error, failure =
        world:executeActions(ability.activation, {
            source = source,
            target = source,
            ability = ability,
        })
    if not result then
        return nil, action_error, failure
    end
    return true
end

local function interruptIfBlocked(world, source, combat)
    if not combat.active or world:allows(source, "act") then return false end
    world.events:emit("ability.interrupted", {
        source_id = source.id,
        ability_id = combat.active.ability_id,
    })
    combat.active = nil
    return true
end

local function resolveAbility(world, source, combat, ability)
    if not combat.active then return end
    local action_failure
    local activated, activation_error = world:transaction(function()
        combat.active.phase = "active"
        combat.active.remaining = ability.duration
        combat.active.hit_targets = {}
        combat.active.hit_count = 0
        world.events:emit("ability.used", {
            source_id = source.id,
            ability_id = ability.id,
        })

        local applied, action_error, failure =
            applyActivation(world, source, ability)
        if not applied then
            action_failure = failure
            return nil, action_error
        end
        return {applied = true}
    end)
    if not activated then
        world.events:emit("ability.action_failed", {
            source_id = source.id,
            ability_id = ability.id,
            scope = "activation",
            action_index =
                action_failure and action_failure.index or nil,
            action_type = action_failure and
                action_failure.action.type or nil,
            error = activation_error,
        })
        world.events:emit("ability.interrupted", {
            source_id = source.id,
            ability_id = ability.id,
            reason = "action_failed",
        })
        combat.active = nil
        return nil, activation_error
    end

    local hits_applied = applyAbilityHits(
        world,
        source,
        combat,
        ability
    )
    if not hits_applied then
        world.events:emit("ability.interrupted", {
            source_id = source.id,
            ability_id = ability.id,
            reason = "action_failed",
        })
        combat.active = nil
        return nil, "ability hit actions failed"
    end
    interruptIfBlocked(world, source, combat)
    return true
end

local function startAbility(world, source, combat, ability)
    combat.cooldown = ability.cooldown
    combat.active = {
        ability_id = ability.id,
        phase = "windup",
        remaining = ability.windup or 0,
    }
    world.events:emit("ability.started", {
        source_id = source.id,
        ability_id = ability.id,
        windup = ability.windup or 0,
    })
    if combat.active.remaining <= 0 then
        resolveAbility(world, source, combat, ability)
    end
end

local input_system = {
    id = "action.combat.player_input",
    phase = "input",
    order = 10,
}

function input_system:update(world)
    local input = world.host.input
    for _, entity in ipairs(
        world:query(
            "control.player",
            "action.combat",
            "action.combat_input"
        )
    ) do
        local binding = entity.components["action.combat_input"]
        local combat = entity.components["action.combat"]
        if not entity.dead then
            for _, item in ipairs(binding.bindings) do
                if input:wasPressed(item.input) then
                    entity.commands.ability =
                        item.ability or combat.primary or
                        combat.abilities[1]
                    break
                end
            end
        end
    end
end

local combat_system = {
    id = "action.combat.resolve",
    phase = "combat",
    order = 0,
}

function combat_system:update(world, dt)
    for _, entity in ipairs(
        world:query("transform", "action.combat")
    ) do
        local combat = entity.components["action.combat"]
        combat.cooldown = util.countdown(combat.cooldown, dt)
        if combat.active then
            if entity.dead or not world:allows(entity, "act") then
                world.events:emit("ability.interrupted", {
                    source_id = entity.id,
                    ability_id = combat.active.ability_id,
                    reason = entity.dead and "death" or "blocked",
                })
                combat.active = nil
            else
                local ability =
                    world.host.catalog:get(combat.active.ability_id)
                combat.active.remaining =
                    util.countdown(combat.active.remaining, dt)
                if combat.active.phase == "windup" and
                   combat.active.remaining <= 0 then
                    resolveAbility(world, entity, combat, ability)
                elseif combat.active.phase == "active" then
                    updateHitTimers(combat.active, dt)
                    local hits_applied =
                        applyAbilityHits(world, entity, combat, ability)
                    if not hits_applied then
                        world.events:emit("ability.interrupted", {
                            source_id = entity.id,
                            ability_id = ability.id,
                            reason = "action_failed",
                        })
                        combat.active = nil
                    elseif not interruptIfBlocked(world, entity, combat) and
                       combat.active.remaining <= 0 then
                        finishAbility(world, entity, combat, ability)
                    end
                elseif combat.active.phase == "recovery" and
                       combat.active.remaining <= 0 then
                    combat.active = nil
                    world.events:emit("ability.finished", {
                        source_id = entity.id,
                        ability_id = ability.id,
                    })
                end
            end
        end

        local requested_ability = entity.commands.ability
        if entity.commands.attack then
            requested_ability = combat.primary or combat.abilities[1]
        end
        if requested_ability and not entity.dead and
           not combat.active and combat.cooldown <= 0 and
           world:allows(entity, "act") then
            local ability = world.host.catalog:get(requested_ability)
            if ability and combat.ability_set[requested_ability] then
                startAbility(world, entity, combat, ability)
            else
                world.events:emit("ability.request_rejected", {
                    source_id = entity.id,
                    ability_id = requested_ability,
                })
            end
        end
        entity.commands.attack = nil
        entity.commands.ability = nil
    end
end

local combat_draw_system = {
    id = "action.combat.telegraph",
    draw_order = 15,
}

function combat_draw_system:draw(world)
    for _, entity in ipairs(
        world:query("transform", "action.combat")
    ) do
        local combat = entity.components["action.combat"]
        if combat.active then
            local ability =
                world.host.catalog:get(combat.active.ability_id)
            local transform = entity.components.transform
            local facing_x, facing_y =
                world:service("motion"):facing(entity)
            local angle = math.atan2(facing_y, facing_x)
            local hitbox = ability.hitbox
            local radius = 18
            if hitbox then
                radius =
                    world:service("action.hitbox"):radius(entity, hitbox)
                local half_cone = math.rad(hitbox.arc_degrees / 2)

                if combat.active.phase == "windup" then
                    love.graphics.setColor(1, 0.25, 0.18, 0.8)
                    love.graphics.setLineWidth(3)
                    love.graphics.arc(
                        "line",
                        transform.x,
                        transform.y,
                        radius,
                        angle - half_cone,
                        angle + half_cone
                    )
                    love.graphics.setLineWidth(1)
                elseif combat.active.phase == "active" then
                    love.graphics.setColor(1, 0.85, 0.25, 0.35)
                    love.graphics.arc(
                        "fill",
                        transform.x,
                        transform.y,
                        radius,
                        angle - half_cone,
                        angle + half_cone
                    )
                end
            elseif combat.active.phase == "windup" then
                love.graphics.setColor(0.3, 0.8, 1, 0.75)
                love.graphics.circle(
                    "line",
                    transform.x,
                    transform.y,
                    radius
                )
            end

            if combat.active.phase == "active" and ability.visual then
                local visual = ability.visual
                local asset = world.host.catalog:get(visual.asset)
                local image = world.host.assets:image(visual.asset)
                local distance = visual.distance or radius * 0.55
                love.graphics.setColor(1, 1, 1, 0.95)
                love.graphics.draw(
                    image,
                    transform.x + facing_x * distance,
                    transform.y + facing_y * distance,
                    angle + (visual.rotation_offset or 0),
                    visual.scale or 1,
                    visual.scale or 1,
                    asset.width / 2,
                    asset.height / 2
                )
            end
        end
    end
end

function feature:register(host)
    host:registerContentKind("ability", {validate = validateAbility})

    host:registerComponent("action.combat", {
        validate = validateCombat,
        create = function(config)
            local abilities = util.deepCopy(config.abilities)
            local ability_set = {}
            for _, ability_id in ipairs(abilities) do
                ability_set[ability_id] = true
            end
            return {
                team = config.team,
                abilities = abilities,
                ability_set = ability_set,
                primary = config.primary or config.abilities[1],
                cooldown = 0,
                active = nil,
            }
        end,
    })
    host.services.lifecycle:registerDeathHandler(
        "action.combat",
        20,
        function(entity, world)
            local combat = entity.components["action.combat"]
            if combat and combat.active then
                world.events:emit("ability.interrupted", {
                    source_id = entity.id,
                    ability_id = combat.active.ability_id,
                    reason = "death",
                })
                combat.active = nil
            end
        end
    )

    host:registerComponent("action.combat_input", {
        requires = {"action.combat"},
        validate = function(config, validator, path, partial)
            validateCombatInput(config, validator, path, partial, host)
        end,
        validateEntity = validateCombatInputEntity,
        create = function(config)
            local bindings = config.bindings and
                util.deepCopy(config.bindings) or {
                    {
                        input = config.attack or "attack",
                        ability = nil,
                    },
                }
            return {bindings = bindings}
        end,
    })

    host:registerGate(
        "move",
        "combat.attack_commitment",
        function(entity, world)
            local combat =
                entity.components and entity.components["action.combat"]
            if not combat or not combat.active then return true end
            local ability =
                world.host.catalog:get(combat.active.ability_id)
            if ability and ability.lock_movement ~= false then
                return false, "attack commitment"
            end
            return true
        end
    )

    host:registerEntityInspector("action.combat", function(entity, world)
        local combat = entity.components["action.combat"]
        if not combat then return end
        local ability = combat.active and
            world.host.catalog:get(combat.active.ability_id) or nil
        return {
            team = combat.team,
            attack_phase = combat.active and combat.active.phase or nil,
            attack_remaining =
                combat.active and combat.active.remaining or nil,
            attack_cooldown = combat.cooldown,
            attack_hit_count = combat.active and
                combat.active.hit_count or nil,
            attack_hitbox = ability and
                util.deepCopy(ability.hitbox) or nil,
        }
    end)

    host:registerSystem(input_system)
    host:registerSystem(combat_system)
    host:registerSystem(combat_draw_system)
end

return feature

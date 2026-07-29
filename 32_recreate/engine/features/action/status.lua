local util = require "engine.core.util"

local feature = {
    id = "action.status",
    requires = {"engine.features.action.health"},
}

local modifier_names = {
    "move_speed",
    "damage_dealt",
    "damage_taken",
}

local modifier_set = {}
for _, name in ipairs(modifier_names) do modifier_set[name] = true end

local function validateActions(actions, validator, host, path)
    actions = validator:array(actions, path, false)
    for index, action in ipairs(actions or {}) do
        host.rules:validateAction(
            action,
            validator,
            string.format("%s[%d]", path, index)
        )
    end
    return actions
end

local function validateColor(color, validator, path)
    color = validator:array(color, path, false)
    if not color then return end
    if #color ~= 3 and #color ~= 4 then
        validator:error(path, "must contain RGB or RGBA values")
    end
    for index, value in ipairs(color) do
        value = validator:number(
            value,
            string.format("%s[%d]", path, index),
            true
        )
        if value and (value < 0 or value > 1) then
            validator:error(
                string.format("%s[%d]", path, index),
                "must be between 0 and 1"
            )
        end
    end
end

local function validateStatus(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name",
            "duration", "stacking", "max_stacks",
            "tick_interval", "tick_actions",
            "on_apply", "on_expire", "modifiers", "color",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    validator:positive(definition.duration, "duration", true)
    local stacking = validator:enum(
        definition.stacking,
        {"refresh", "stack"},
        "stacking",
        false
    ) or "refresh"
    local max_stacks = validator:number(
        definition.max_stacks,
        "max_stacks",
        false
    )
    if max_stacks and
       (max_stacks < 1 or max_stacks % 1 ~= 0) then
        validator:error("max_stacks", "must be a positive integer")
    end
    if stacking == "refresh" and max_stacks and max_stacks ~= 1 then
        validator:error(
            "max_stacks",
            "must be 1 when stacking is 'refresh'"
        )
    end

    local tick_interval = validator:positive(
        definition.tick_interval,
        "tick_interval",
        false
    )
    local tick_actions = validateActions(
        definition.tick_actions,
        validator,
        host,
        "tick_actions"
    )
    if tick_actions and #tick_actions == 0 then
        validator:error("tick_actions", "must not be empty")
    end
    if tick_actions and not tick_interval then
        validator:error("tick_interval", "is required with tick_actions")
    elseif tick_interval and not tick_actions then
        validator:error("tick_actions", "is required with tick_interval")
    end
    validateActions(definition.on_apply, validator, host, "on_apply")
    validateActions(definition.on_expire, validator, host, "on_expire")

    local modifiers =
        validator:table(definition.modifiers, "modifiers", false)
    if modifiers then
        validator:keys(modifiers, modifier_names, "modifiers")
        for name, value in pairs(modifiers) do
            if modifier_set[name] then
                validator:positive(
                    value,
                    "modifiers." .. name,
                    true
                )
            end
        end
    end
    validateColor(definition.color, validator, "color")
end

local function validateStatusComponent(config, validator, path)
    if not validator:table(config, path, true) then return end
    validator:keys(config, {"immune"}, path)
    local immune = validator:array(
        config.immune,
        path .. ".immune",
        false
    )
    local seen = {}
    for index, status_id in ipairs(immune or {}) do
        local item_path = string.format("%s.immune[%d]", path, index)
        validator:reference(status_id, "status", item_path)
        if seen[status_id] then
            validator:error(item_path, "duplicates another immunity")
        end
        seen[status_id] = true
    end
end

local function statusState(entity)
    return entity and entity.components and
        entity.components["action.status"] or nil
end

local function executeActions(
    world,
    actions,
    source,
    target,
    definition,
    entry,
    damage_kind
)
    local result, action_error, failure =
        world:executeActions(actions, {
            source = source,
            target = target,
            status = definition,
            status_stacks = entry.stacks,
            damage_kind = damage_kind,
        })
    if not result then
        return nil, action_error, failure
    end
    return result
end

local status = {}

local function emitActionFailure(
    world,
    target,
    definition,
    scope,
    action_error,
    failure
)
    world.events:emit("status.action_failed", {
        target_id = target and target.id or nil,
        status_id = definition and definition.id or nil,
        scope = scope,
        action_index = failure and failure.index or nil,
        action_type = failure and failure.action.type or nil,
        error = action_error,
    })
end

function status:has(entity, status_id)
    local state = statusState(entity)
    return state ~= nil and state.active[status_id] ~= nil
end

function status:multiplier(entity, modifier)
    local state = statusState(entity)
    if not state then return 1 end
    local result = 1
    for _, status_id in ipairs(util.sortedKeys(state.active)) do
        local entry = state.active[status_id]
        local definition = entry.definition
        local value = definition and definition.modifiers and
            definition.modifiers[modifier]
        if value then result = result * value ^ entry.stacks end
    end
    return result
end

local function sourceFor(world, entry)
    return entry.source_id and world:get(entry.source_id) or nil
end

function status:apply(world, target, status_id, options)
    options = options or {}
    local state = statusState(target)
    local definition = world.host.catalog:get(status_id)
    if not state or not definition or definition.kind ~= "status" then
        return nil, "target cannot receive status '" .. tostring(status_id) .. "'"
    end
    if state.immune[status_id] then
        world.events:emit("status.resisted", {
            target_id = target.id,
            source_id = options.source and options.source.id or nil,
            status_id = status_id,
        })
        return {
            applied = false,
            resisted = true,
            status_id = status_id,
        }
    end

    local action_failure
    local result, apply_error = world:transaction(function()
        local duration = options.duration or definition.duration
        local requested_stacks = options.stacks or 1
        local maximum =
            definition.stacking == "stack" and
            (definition.max_stacks or 99) or 1
        local entry = state.active[status_id]
        local event_name
        if entry then
            local previous_stacks = entry.stacks
            if definition.stacking == "stack" then
                entry.stacks = math.min(
                    maximum,
                    entry.stacks + requested_stacks
                )
            else
                entry.stacks = 1
            end
            entry.remaining = duration
            entry.source_id =
                options.source and options.source.id or entry.source_id
            entry.revision = (entry.revision or 1) + 1
            event_name = entry.stacks > previous_stacks and
                "status.stacked" or "status.refreshed"
        else
            state.sequence = (state.sequence or 0) + 1
            entry = {
                status_id = status_id,
                definition = definition,
                source_id = options.source and options.source.id or nil,
                stacks = math.min(maximum, requested_stacks),
                remaining = duration,
                tick_remaining = definition.tick_interval,
                instance = state.sequence,
                revision = 1,
            }
            state.active[status_id] = entry
            event_name = "status.applied"
            local applied, action_error, failure = executeActions(
                world,
                definition.on_apply,
                options.source,
                target,
                definition,
                entry
            )
            if not applied then
                action_failure = failure
                return nil, action_error
            end
        end

        if state.active[status_id] ~= entry then
            return {
                applied = true,
                active = state.active[status_id] ~= nil,
                replaced_during_apply = true,
                status_id = status_id,
            }
        end
        world.events:emit(event_name, {
            target_id = target.id,
            source_id = entry.source_id,
            status_id = status_id,
            stacks = entry.stacks,
            duration = duration,
        })
        return {
            applied = true,
            active = true,
            status_id = status_id,
            stacks = entry.stacks,
            duration = duration,
        }
    end)
    if not result then
        emitActionFailure(
            world,
            target,
            definition,
            "apply",
            apply_error,
            action_failure
        )
        return nil, apply_error
    end
    return result
end

function status:remove(world, target, status_id, reason)
    local state = statusState(target)
    local entry = state and state.active[status_id]
    if not entry then
        return {
            applied = false,
            status_id = status_id,
        }
    end
    state.active[status_id] = nil
    world.events:emit("status.removed", {
        target_id = target.id,
        source_id = entry.source_id,
        status_id = status_id,
        stacks = entry.stacks,
        reason = reason or "removed",
    })
    return {
        applied = true,
        status_id = status_id,
        stacks = entry.stacks,
    }
end

local status_system = {
    id = "action.status.timers",
    phase = "resolution",
    order = -20,
}

function status_system:update(world, dt)
    for _, entity in ipairs(world:query("action.status")) do
        local state = statusState(entity)
        for _, status_id in ipairs(util.sortedKeys(state.active)) do
            local entry = state.active[status_id]
            if entry then
                local definition = entry.definition
                local original_remaining = entry.remaining
                local original_tick = entry.tick_remaining
                local revision = entry.revision
                local active_dt = math.min(dt, entry.remaining)
                entry.remaining = util.countdown(entry.remaining, dt)
                local failed = false

                if definition.tick_interval then
                    entry.tick_remaining =
                        entry.tick_remaining - active_dt
                    while entry.tick_remaining <= 1e-9 do
                        local tick_actions = {}
                        for _ = 1, entry.stacks do
                            for _, action in ipairs(
                                definition.tick_actions
                            ) do
                                tick_actions[#tick_actions + 1] = action
                            end
                        end
                        local ticked, action_error, failure =
                            executeActions(
                                world,
                                tick_actions,
                                sourceFor(world, entry),
                                entity,
                                definition,
                                entry,
                                "periodic"
                            )
                        if not ticked then
                            if state.active[status_id] == entry then
                                entry.remaining = original_remaining
                                entry.tick_remaining = original_tick
                            end
                            emitActionFailure(
                                world,
                                entity,
                                definition,
                                "tick",
                                action_error,
                                failure
                            )
                            failed = true
                            break
                        end
                        world.events:emit("status.ticked", {
                            target_id = entity.id,
                            source_id = entry.source_id,
                            status_id = status_id,
                            stacks = entry.stacks,
                        })
                        if state.active[status_id] ~= entry or
                           entry.revision ~= revision or entity.dead then
                            break
                        end
                        entry.tick_remaining =
                            entry.tick_remaining +
                                definition.tick_interval
                        if active_dt == 0 then break end
                    end
                end

                if not failed and state.active[status_id] == entry and
                   entry.revision == revision and
                   entry.remaining == 0 then
                    local action_failure
                    local expired, expire_error =
                        world:transaction(function()
                            state.active[status_id] = nil
                            local executed, action_error, failure =
                                executeActions(
                                    world,
                                    definition.on_expire,
                                    sourceFor(world, entry),
                                    entity,
                                    definition,
                                    entry
                                )
                            if not executed then
                                action_failure = failure
                                return nil, action_error
                            end
                            world.events:emit("status.expired", {
                                target_id = entity.id,
                                source_id = entry.source_id,
                                status_id = status_id,
                                stacks = entry.stacks,
                            })
                            return {applied = true}
                        end)
                    if not expired then
                        emitActionFailure(
                            world,
                            entity,
                            definition,
                            "expire",
                            expire_error,
                            action_failure
                        )
                    end
                end
            end
        end
    end
end

local status_draw_system = {
    id = "action.status.feedback",
    draw_order = 26,
}

function status_draw_system:draw(world)
    for _, entity in ipairs(
        world:query("transform", "action.status")
    ) do
        local state = statusState(entity)
        local transform = entity.components.transform
        local index = 0
        for _, status_id in ipairs(util.sortedKeys(state.active)) do
            index = index + 1
            local entry = state.active[status_id]
            local definition = entry.definition
            local color = definition.color or {0.75, 0.35, 1, 1}
            love.graphics.setColor(
                color[1],
                color[2],
                color[3],
                color[4] or 1
            )
            love.graphics.circle(
                "fill",
                transform.x - 8 + (index - 1) * 9,
                transform.y + 22,
                3
            )
        end
    end
end

function feature:register(host)
    host:registerContentKind("status", {
        validate = function(definition, validator)
            validateStatus(definition, validator, host)
        end,
    })
    host:registerComponent("action.status", {
        validate = validateStatusComponent,
        create = function(config)
            local immune = {}
            for _, status_id in ipairs(config.immune or {}) do
                immune[status_id] = true
            end
            return {
                immune = immune,
                active = {},
                sequence = 0,
            }
        end,
    })
    host.services.lifecycle:registerDeathHandler(
        "action.status",
        70,
        function(entity, world)
            local state = statusState(entity)
            if not state then return end
            for _, status_id in ipairs(util.sortedKeys(state.active)) do
                local entry = state.active[status_id]
                world.events:emit("status.removed", {
                    target_id = entity.id,
                    source_id = entry.source_id,
                    status_id = status_id,
                    stacks = entry.stacks,
                    reason = "death",
                })
            end
            state.active = {}
        end
    )

    host.rules:registerAction("apply_status", {
        validate = function(action, validator, path)
            validator:keys(
                action,
                {"type", "status", "duration", "stacks"},
                path
            )
            validator:reference(
                action.status,
                "status",
                path .. ".status"
            )
            validator:positive(
                action.duration,
                path .. ".duration",
                false
            )
            local stacks = validator:number(
                action.stacks,
                path .. ".stacks",
                false
            )
            if stacks and (stacks < 1 or stacks % 1 ~= 0) then
                validator:error(
                    path .. ".stacks",
                    "must be a positive integer"
                )
            end
        end,
        execute = function(action, context)
            return status:apply(
                context.world,
                context.target,
                action.status,
                {
                    source = context.source,
                    duration = action.duration,
                    stacks = action.stacks,
                }
            )
        end,
    })
    host.rules:registerAction("remove_status", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "status"}, path)
            validator:reference(
                action.status,
                "status",
                path .. ".status"
            )
        end,
        execute = function(action, context)
            return status:remove(
                context.world,
                context.target,
                action.status,
                "action"
            )
        end,
    })
    host.rules:registerCondition("has_status", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "status", "stacks_at_least"},
                path
            )
            validator:reference(
                condition.status,
                "status",
                path .. ".status"
            )
            local stacks = validator:number(
                condition.stacks_at_least,
                path .. ".stacks_at_least",
                false
            )
            if stacks and (stacks < 1 or stacks % 1 ~= 0) then
                validator:error(
                    path .. ".stacks_at_least",
                    "must be a positive integer"
                )
            end
        end,
        evaluate = function(condition, context)
            local state = statusState(context.target)
            local entry = state and state.active[condition.status]
            return entry ~= nil and
                entry.stacks >= (condition.stacks_at_least or 1)
        end,
    })

    host.rules:registerActionInterceptor(
        "damage",
        "status.damage_modifiers",
        5,
        function(action, context, nextHandler)
            if context.debug then return nextHandler() end
            local outgoing = status:multiplier(
                context.source,
                "damage_dealt"
            )
            local incoming = status:multiplier(
                context.target,
                "damage_taken"
            )
            local multiplier = outgoing * incoming
            if multiplier == 1 then return nextHandler() end
            local adjusted = util.deepCopy(action)
            adjusted.amount = adjusted.amount * multiplier
            return nextHandler(adjusted)
        end
    )

    host:registerService("status", status)
    host:registerEntityInspector("action.status", function(entity)
        local state = statusState(entity)
        if not state then return end
        local active = {}
        for _, status_id in ipairs(util.sortedKeys(state.active)) do
            local entry = state.active[status_id]
            active[#active + 1] = {
                id = status_id,
                stacks = entry.stacks,
                remaining = entry.remaining,
                tick_remaining = entry.tick_remaining,
                source_id = entry.source_id,
            }
        end
        return {
            status_count = #active,
            statuses = active,
        }
    end)
    host:registerDebugDrawer("action.status", function(world, options)
        if not options.labels then return end
        for _, entity in ipairs(
            world:query("transform", "action.status")
        ) do
            local state = statusState(entity)
            local labels = {}
            for _, status_id in ipairs(util.sortedKeys(state.active)) do
                local entry = state.active[status_id]
                labels[#labels + 1] = string.format(
                    "%s x%d %.1fs",
                    status_id,
                    entry.stacks,
                    entry.remaining
                )
            end
            if #labels > 0 then
                local transform = entity.components.transform
                love.graphics.setColor(1, 0.55, 0.2, 0.95)
                love.graphics.printf(
                    table.concat(labels, "\n"),
                    transform.x - 90,
                    transform.y + 32,
                    180,
                    "center"
                )
            end
        end
    end)
    host:registerSystem(status_system)
    host:registerSystem(status_draw_system)
end

return feature

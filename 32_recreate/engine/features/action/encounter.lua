local util = require "engine.core.util"

local feature = {
    id = "action.encounter",
    requires = {
        "engine.features.world",
        "engine.features.action.health",
    },
}

local function validateActions(actions, validator, host, path)
    actions = validator:array(actions, path, false)
    for index, action in ipairs(actions or {}) do
        host.rules:validateAction(
            action,
            validator,
            string.format("%s[%d]", path, index)
        )
    end
end

local function validatePhase(
    phase,
    validator,
    host,
    path,
    spawn_ids,
    phase_ids
)
    if not validator:table(phase, path, true) then return end
    validator:keys(
        phase,
        {"id", "spawn", "health_ratio_at_most", "actions"},
        path
    )
    local id = validator:string(phase.id, path .. ".id", true)
    if id and phase_ids[id] then
        validator:error(path .. ".id", "duplicates another boss phase id")
    elseif id then
        phase_ids[id] = true
    end
    local spawn = validator:string(
        phase.spawn,
        path .. ".spawn",
        true
    )
    if spawn and not spawn_ids[spawn] then
        validator:error(
            path .. ".spawn",
            "references no spawn in this wave"
        )
    end
    local threshold = validator:number(
        phase.health_ratio_at_most,
        path .. ".health_ratio_at_most",
        true
    )
    if threshold and (threshold <= 0 or threshold > 1) then
        validator:error(
            path .. ".health_ratio_at_most",
            "must be greater than 0 and at most 1"
        )
    end
    validateActions(phase.actions, validator, host, path .. ".actions")
end

local function validateEncounter(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name",
            "target_tag", "waves", "on_complete",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    validator:string(definition.target_tag, "target_tag", false)
    local waves = validator:array(definition.waves, "waves", true)
    if waves and #waves == 0 then
        validator:error("waves", "must contain at least one wave")
    end
    local wave_ids = {}
    for wave_index, wave in ipairs(waves or {}) do
        local path = string.format("waves[%d]", wave_index)
        if validator:table(wave, path, true) then
            validator:keys(
                wave,
                {
                    "id", "delay", "spawns", "boss_phases",
                    "on_start", "on_complete",
                },
                path
            )
            local wave_id =
                validator:string(wave.id, path .. ".id", true)
            if wave_id and wave_ids[wave_id] then
                validator:error(
                    path .. ".id",
                    "duplicates another wave id"
                )
            elseif wave_id then
                wave_ids[wave_id] = true
            end
            local delay =
                validator:number(wave.delay, path .. ".delay", false)
            if delay and delay < 0 then
                validator:error(
                    path .. ".delay",
                    "must not be negative"
                )
            end

            local spawns = validator:array(
                wave.spawns,
                path .. ".spawns",
                true
            )
            if spawns and #spawns == 0 then
                validator:error(
                    path .. ".spawns",
                    "must contain at least one actor"
                )
            end
            local spawn_ids = {}
            for spawn_index, spawn in ipairs(spawns or {}) do
                host.services.actor:validateInstance(
                    spawn,
                    validator,
                    string.format(
                        "%s.spawns[%d]",
                        path,
                        spawn_index
                    ),
                    spawn_ids
                )
            end

            local phases = validator:array(
                wave.boss_phases,
                path .. ".boss_phases",
                false
            )
            local phase_ids = {}
            for phase_index, phase in ipairs(phases or {}) do
                validatePhase(
                    phase,
                    validator,
                    host,
                    string.format(
                        "%s.boss_phases[%d]",
                        path,
                        phase_index
                    ),
                    spawn_ids,
                    phase_ids
                )
            end
            validateActions(
                wave.on_start,
                validator,
                host,
                path .. ".on_start"
            )
            validateActions(
                wave.on_complete,
                validator,
                host,
                path .. ".on_complete"
            )
        end
    end
    validateActions(
        definition.on_complete,
        validator,
        host,
        "on_complete"
    )
end

local function validatePlacements(
    placements,
    validator,
    path,
    stage
)
    placements = validator:array(placements, path, false)
    local seen = {}
    local generated_ids = {}
    for _, spawn in ipairs(stage.spawns or {}) do
        generated_ids[spawn.id] = "stage spawn"
    end
    for index, placement in ipairs(placements or {}) do
        local item_path = string.format("%s[%d]", path, index)
        if validator:table(placement, item_path, true) then
            validator:keys(
                placement,
                {"id", "encounter", "position", "auto_start"},
                item_path
            )
            local id =
                validator:string(placement.id, item_path .. ".id", true)
            if id and seen[id] then
                validator:error(
                    item_path .. ".id",
                    "duplicates another encounter placement id"
                )
            elseif id then
                seen[id] = true
            end
            local definition = validator:reference(
                placement.encounter,
                "encounter",
                item_path .. ".encounter"
            )
            local position = validator:table(
                placement.position,
                item_path .. ".position",
                false
            )
            if position then
                validator:keys(
                    position,
                    {"x", "y"},
                    item_path .. ".position"
                )
                validator:number(
                    position.x,
                    item_path .. ".position.x",
                    true
                )
                validator:number(
                    position.y,
                    item_path .. ".position.y",
                    true
                )
            end
            validator:boolean(
                placement.auto_start,
                item_path .. ".auto_start",
                false
            )

            for wave_index, wave in ipairs(
                definition and definition.waves or {}
            ) do
                for _, spawn in ipairs(wave.spawns or {}) do
                    local entity_id = string.format(
                        "encounter.%s.wave.%d.%s",
                        id or "?",
                        wave_index,
                        spawn.id
                    )
                    if generated_ids[entity_id] then
                        validator:error(
                            item_path,
                            "generates duplicate entity id '" ..
                                entity_id .. "'"
                        )
                    else
                        generated_ids[entity_id] = item_path
                    end
                end
            end
        end
    end
end

local function stateFor(world, encounter_id)
    if not world then return nil end
    local feature_state = world.feature_state.encounter
    return feature_state and feature_state.by_id[encounter_id] or nil
end

local function actionTarget(world, definition)
    return world:findByTag(definition.target_tag or "player")[1]
end

local function executeActions(
    world,
    actions,
    context,
    failure_scope
)
    local result, action_error, failure =
        world:executeActions(actions, context)
    if not result then
        return nil, action_error, {
            encounter_id = context.encounter_id,
            wave_id = context.wave_id,
            phase_id = context.phase_id,
            scope = failure_scope,
            action_index = failure and failure.index or nil,
            action_type = failure and failure.action.type or nil,
            error = action_error,
        }
    end
    return true
end

local encounter = {}

local function failEncounter(world, state, failure, failure_error)
    state.status = "failed"
    state.error = tostring(failure_error or "encounter action failed")
    failure = failure or {
        encounter_id = state.id,
        error = state.error,
    }
    failure.error = state.error
    world.events:emit("encounter.action_failed", failure)
end

function encounter:start(world, encounter_id)
    local state = stateFor(world, encounter_id)
    if not state then
        return nil, "unknown encounter '" .. tostring(encounter_id) .. "'"
    end
    if state.status ~= "idle" then
        return {
            applied = false,
            encounter_id = encounter_id,
            status = state.status,
        }
    end
    state.status = "pending"
    state.remaining = state.definition.waves[1].delay or 0
    world.events:emit("encounter.started", {
        encounter_id = encounter_id,
        definition_id = state.definition.id,
    })
    return {
        applied = true,
        encounter_id = encounter_id,
        status = state.status,
    }
end

function encounter:state(world, encounter_id)
    return stateFor(world, encounter_id)
end

local function beginWave(world, state)
    local action_failure
    local result, begin_error = world:transaction(function()
        state.wave_index = state.wave_index + 1
        local wave = state.definition.waves[state.wave_index]
        state.status = "active"
        state.error = nil
        state.remaining = 0
        state.live_ids = {}
        state.spawn_entities = {}
        state.entered_phases = {}

        local target = actionTarget(world, state.definition)
        local executed, action_error, failure = executeActions(
            world,
            wave.on_start,
            {
                source = target,
                target = target,
                encounter_id = state.id,
                wave_id = wave.id,
            },
            "wave_start"
        )
        if not executed then
            action_failure = failure
            return nil, action_error
        end

        for _, spawn in ipairs(wave.spawns) do
            local instance = util.deepCopy(spawn)
            instance.id = string.format(
                "encounter.%s.wave.%d.%s",
                state.id,
                state.wave_index,
                spawn.id
            )
            instance.position = {
                x = state.x + spawn.position.x,
                y = state.y + spawn.position.y,
            }
            local entity, spawn_error =
                world:spawn(spawn.actor, instance)
            if not entity then
                return nil, "validated encounter spawn failed: " ..
                    tostring(spawn_error)
            end
            state.live_ids[#state.live_ids + 1] = entity.id
            state.spawn_entities[spawn.id] = entity.id
        end

        world.events:emit("encounter.wave_started", {
            encounter_id = state.id,
            wave_id = wave.id,
            wave_index = state.wave_index,
            actor_count = #state.live_ids,
        })
        return {applied = true}
    end)
    if not result then
        failEncounter(world, state, action_failure, begin_error)
        return nil, begin_error
    end
    return true
end

local function allDefeated(world, state)
    for _, entity_id in ipairs(state.live_ids) do
        local entity = world:get(entity_id)
        if entity and not entity.dead then return false end
    end
    return true
end

local function updateBossPhases(world, state, wave)
    for _, phase in ipairs(wave.boss_phases or {}) do
        if not state.entered_phases[phase.id] then
            local entity_id = state.spawn_entities[phase.spawn]
            local boss = entity_id and world:get(entity_id)
            local health = boss and
                boss.components["action.health"] or nil
            if health and not boss.dead and
               health.current / health.max <=
                   phase.health_ratio_at_most then
                local action_failure
                local result, phase_error =
                    world:transaction(function()
                        state.entered_phases[phase.id] = true
                        local executed, action_error, failure =
                            executeActions(
                                world,
                                phase.actions,
                                {
                                    source = boss,
                                    target = boss,
                                    encounter_id = state.id,
                                    wave_id = wave.id,
                                    phase_id = phase.id,
                                },
                                "boss_phase"
                            )
                        if not executed then
                            action_failure = failure
                            return nil, action_error
                        end
                        world.events:emit("boss.phase_entered", {
                            encounter_id = state.id,
                            wave_id = wave.id,
                            phase_id = phase.id,
                            entity_id = boss.id,
                            health_ratio = health.current / health.max,
                        })
                        return {applied = true}
                    end)
                if not result then
                    failEncounter(
                        world,
                        state,
                        action_failure,
                        phase_error
                    )
                    return nil, phase_error
                end
            end
        end
    end
    return true
end

local function completeWave(world, state, wave)
    local action_failure
    local result, complete_error = world:transaction(function()
        local target = actionTarget(world, state.definition)
        local executed, action_error, failure = executeActions(
            world,
            wave.on_complete,
            {
                source = target,
                target = target,
                encounter_id = state.id,
                wave_id = wave.id,
            },
            "wave_complete"
        )
        if not executed then
            action_failure = failure
            return nil, action_error
        end
        world.events:emit("encounter.wave_completed", {
            encounter_id = state.id,
            wave_id = wave.id,
            wave_index = state.wave_index,
        })

        local next_wave = state.definition.waves[state.wave_index + 1]
        if next_wave then
            state.status = "pending"
            state.remaining = next_wave.delay or 0
        else
            state.status = "completed"
            local finished, finish_error, finish_failure =
                executeActions(
                    world,
                    state.definition.on_complete,
                    {
                        source = target,
                        target = target,
                        encounter_id = state.id,
                    },
                    "encounter_complete"
                )
            if not finished then
                action_failure = finish_failure
                return nil, finish_error
            end
            world.events:emit("encounter.completed", {
                encounter_id = state.id,
                definition_id = state.definition.id,
            })
        end
        return {applied = true}
    end)
    if not result then
        failEncounter(world, state, action_failure, complete_error)
        return nil, complete_error
    end
    return true
end

local encounter_system = {
    id = "action.encounter.progress",
    phase = "resolution",
    order = 200,
}

function encounter_system:update(world, dt)
    local feature_state = world.feature_state.encounter
    if not feature_state then return end
    for _, state in ipairs(feature_state.order) do
        if state.status == "pending" then
            state.remaining = util.countdown(state.remaining, dt)
                if state.remaining == 0 then beginWave(world, state) end
        elseif state.status == "active" then
            local wave = state.definition.waves[state.wave_index]
            local phases_updated = updateBossPhases(world, state, wave)
            if phases_updated and allDefeated(world, state) then
                completeWave(world, state, wave)
            end
        end
    end
end

function feature:register(host)
    host:registerContentKind("encounter", {
        validate = function(definition, validator)
            validateEncounter(definition, validator, host)
        end,
    })
    host:registerStageSection("encounters", {
        priority = 70,
        validate = function(placements, validator, path, stage)
            validatePlacements(
                placements,
                validator,
                path,
                stage
            )
        end,
        load = function(world, placements)
            local feature_state = {
                by_id = {},
                order = {},
            }
            world.feature_state.encounter = feature_state
            for _, placement in ipairs(placements or {}) do
                local definition =
                    host.catalog:get(placement.encounter)
                local state = {
                    id = placement.id,
                    definition = definition,
                    x = placement.position and
                        placement.position.x or 0,
                    y = placement.position and
                        placement.position.y or 0,
                    status = "idle",
                    wave_index = 0,
                    remaining = 0,
                    live_ids = {},
                    spawn_entities = {},
                    entered_phases = {},
                    auto_start = placement.auto_start ~= false,
                }
                feature_state.by_id[state.id] = state
                feature_state.order[#feature_state.order + 1] = state
            end
            table.sort(feature_state.order, function(left, right)
                return left.id < right.id
            end)
            for _, state in ipairs(feature_state.order) do
                if state.auto_start then
                    encounter:start(world, state.id)
                end
            end
            return true
        end,
    })
    host.rules:registerAction("start_encounter", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "encounter"}, path)
            validator:string(
                action.encounter,
                path .. ".encounter",
                true
            )
        end,
        execute = function(action, context)
            return encounter:start(
                context.world,
                action.encounter
            )
        end,
    })
    host.rules:registerCondition("encounter_state", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "encounter", "state"},
                path
            )
            validator:string(
                condition.encounter,
                path .. ".encounter",
                true
            )
            validator:enum(
                condition.state,
                {"idle", "pending", "active", "completed", "failed"},
                path .. ".state",
                true
            )
        end,
        evaluate = function(condition, context)
            local state = stateFor(
                context.world,
                condition.encounter
            )
            return state ~= nil and state.status == condition.state
        end,
    })

    host:registerService("encounter", encounter)
    host:registerWorldInspector("action.encounter", function(world)
        local feature_state = world.feature_state.encounter
        local result = {}
        for _, state in ipairs(
            feature_state and feature_state.order or {}
        ) do
            local living = 0
            for _, entity_id in ipairs(state.live_ids) do
                local entity = world:get(entity_id)
                if entity and not entity.dead then living = living + 1 end
            end
            result[#result + 1] = {
                id = state.id,
                definition_id = state.definition.id,
                status = state.status,
                wave_index = state.wave_index,
                wave_id = state.wave_index > 0 and
                    state.definition.waves[state.wave_index].id or nil,
                remaining = state.remaining,
                error = state.error,
                living = living,
                entered_phases =
                    util.sortedKeys(state.entered_phases),
            }
        end
        return {
            encounters = result,
            encounter_count = #result,
        }
    end)
    host:registerDebugDrawer("action.encounter", function(world, options)
        if not options.labels then return end
        local feature_state = world.feature_state.encounter
        for _, state in ipairs(
            feature_state and feature_state.order or {}
        ) do
            love.graphics.setColor(1, 0.72, 0.2, 0.95)
            love.graphics.printf(
                string.format(
                    "%s: %s W%d",
                    state.id,
                    state.status,
                    state.wave_index
                ),
                state.x - 100,
                state.y - 16,
                200,
                "center"
            )
        end
    end)
    host:registerSystem(encounter_system)
end

return feature

local util = require "engine.core.util"
local Schema = require "engine.runtime.session_schema"

local feature = {
    id = "rpg.quest",
    requires = {"engine.features.session"},
}

local function positiveInteger(value, validator, path, required)
    value = validator:number(value, path, required)
    if value and (value < 1 or value % 1 ~= 0) then
        validator:error(path, "must be a positive integer")
        return nil
    end
    return value
end

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

local function validateWhere(where, validator, path)
    where = validator:table(where, path, false)
    for key, value in pairs(where or {}) do
        if type(key) ~= "string" or key == "" then
            validator:error(path, "filter keys must be non-empty strings")
        elseif type(value) ~= "string" and
               type(value) ~= "number" and
               type(value) ~= "boolean" then
            validator:error(
                path .. "." .. key,
                "must be a string, number, or boolean"
            )
        end
    end
end

local function validateQuest(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "name_key",
            "description", "description_key", "objectives",
            "on_start", "on_complete",
        },
        "content"
    )
    local name = validator:string(definition.name, "name", false)
    local name_key = validator:string(
        definition.name_key,
        "name_key",
        false
    )
    if not name and not name_key then
        validator:error("name", "requires name or name_key")
    end
    validator:string(
        definition.description,
        "description",
        false
    )
    validator:string(
        definition.description_key,
        "description_key",
        false
    )
    local objectives = validator:array(
        definition.objectives,
        "objectives",
        true
    )
    if objectives and #objectives == 0 then
        validator:error(
            "objectives",
            "must contain at least one objective"
        )
    end
    local seen = {}
    for index, objective in ipairs(objectives or {}) do
        local path = string.format("objectives[%d]", index)
        if validator:table(objective, path, true) then
            validator:keys(
                objective,
                {"id", "event", "count", "where"},
                path
            )
            local id = validator:string(
                objective.id,
                path .. ".id",
                true
            )
            if id and seen[id] then
                validator:error(
                    path .. ".id",
                    "duplicates another objective id"
                )
            elseif id then
                seen[id] = true
            end
            validator:string(
                objective.event,
                path .. ".event",
                true
            )
            positiveInteger(
                objective.count,
                validator,
                path .. ".count",
                false
            )
            validateWhere(
                objective.where,
                validator,
                path .. ".where"
            )
        end
    end
    validateActions(definition.on_start, validator, host, "on_start")
    validateActions(
        definition.on_complete,
        validator,
        host,
        "on_complete"
    )
end

local function matches(payload, where)
    for key, expected in pairs(where or {}) do
        if payload[key] ~= expected then return false end
    end
    return true
end

function feature:register(host)
    local session = host.services.session
    local state = session:registerSection("rpg.quests", {
        version = 1,
        defaults = {quests = {}},
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "rpg.quests",
                {"quests"},
                {"quests"}
            )
            if not valid then return nil, value_error end
            return Schema.map(
                value.quests,
                "rpg.quests.quests",
                function(entry, path)
                    local entry_valid, entry_error = Schema.object(
                        entry,
                        path,
                        {"status", "objectives"},
                        {"status", "objectives"}
                    )
                    if not entry_valid then
                        return nil, entry_error
                    end
                    entry_valid, entry_error = Schema.enum(
                        entry.status,
                        path .. ".status",
                        {"active", "completed"}
                    )
                    if not entry_valid then
                        return nil, entry_error
                    end
                    return Schema.map(
                        entry.objectives,
                        path .. ".objectives",
                        function(count, objective_path)
                            return Schema.nonNegativeInteger(
                                count,
                                objective_path
                            )
                        end
                    )
                end
            )
        end,
    })
    local quest = {}

    local function definition(quest_id)
        local value = host.catalog:get(quest_id)
        if value and value.kind == "quest" then return value end
        return nil
    end

    local function entryFor(quest_id)
        return state.quests[quest_id]
    end

    local function executeActions(
        world,
        definition_value,
        actions,
        scope,
        payload
    )
        local source = payload and payload.source_id and
            world:get(payload.source_id) or nil
        local target = world:findByTag("player")[1]
        local result, action_error, failure =
            world:executeActions(actions, {
                source = source,
                target = target,
                quest = definition_value,
                quest_id = definition_value.id,
                event_payload = payload,
            })
        if not result then
            return nil, action_error, {
                quest_id = definition_value.id,
                scope = scope,
                action_index = failure and failure.index or nil,
                action_type = failure and failure.action.type or nil,
                error = action_error,
            }
        end
        return true
    end

    local function emitActionFailure(world, failure)
        if failure then
            world.events:emit("quest.action_failed", failure)
        end
    end

    local function completeIfReady(world, definition_value, entry, payload)
        for _, objective in ipairs(definition_value.objectives) do
            if (entry.objectives[objective.id] or 0) <
               (objective.count or 1) then
                return false
            end
        end
        entry.status = "completed"
        local executed, action_error, failure = executeActions(
            world,
            definition_value,
            definition_value.on_complete,
            "complete",
            payload
        )
        if not executed then return nil, action_error, failure end
        world.events:emit("quest.completed", {
            quest_id = definition_value.id,
        })
        return true
    end

    function quest:start(world, quest_id)
        local definition_value = definition(quest_id)
        if not definition_value then
            return nil, "unknown quest '" .. tostring(quest_id) .. "'"
        end
        local existing = entryFor(quest_id)
        if existing then
            return {
                applied = false,
                quest_id = quest_id,
                status = existing.status,
            }
        end
        local action_failure
        local result, start_error = world:transaction(function()
            local entry = {
                status = "active",
                objectives = {},
            }
            for _, objective in ipairs(definition_value.objectives) do
                entry.objectives[objective.id] = 0
            end
            state.quests[quest_id] = entry
            local executed, action_error, failure = executeActions(
                world,
                definition_value,
                definition_value.on_start,
                "start"
            )
            if not executed then
                action_failure = failure
                return nil, action_error
            end
            world.events:emit("quest.started", {
                quest_id = quest_id,
            })
            return {
                applied = true,
                quest_id = quest_id,
                status = entry.status,
            }
        end)
        if not result then
            emitActionFailure(world, action_failure)
            return nil, start_error
        end
        return result
    end

    function quest:state(quest_id)
        return entryFor(quest_id)
    end

    local function processEvent(world, event_name, payload)
        for _, definition_value in ipairs(host.catalog:all()) do
            local entry = definition_value.kind == "quest" and
                entryFor(definition_value.id) or nil
            if entry and entry.status == "active" then
                local matching = {}
                for _, objective in ipairs(definition_value.objectives) do
                    local goal = objective.count or 1
                    local current =
                        entry.objectives[objective.id] or 0
                    if objective.event == event_name and
                       current < goal and
                       matches(payload, objective.where) then
                        matching[#matching + 1] = objective
                    end
                end
                if #matching > 0 then
                    local action_failure
                    local progressed, progress_error =
                        world:transaction(function()
                            for _, objective in ipairs(matching) do
                                local goal = objective.count or 1
                                local current = math.min(
                                    goal,
                                    (entry.objectives[objective.id] or 0) + 1
                                )
                                entry.objectives[objective.id] = current
                                world.events:emit(
                                    "quest.objective_progress",
                                    {
                                        quest_id = definition_value.id,
                                        objective_id = objective.id,
                                        count = current,
                                        goal = goal,
                                    }
                                )
                            end
                            local completed, complete_error, failure =
                                completeIfReady(
                                    world,
                                    definition_value,
                                    entry,
                                    payload
                                )
                            if completed == nil then
                                action_failure = failure
                                return nil, complete_error
                            end
                            return {
                                applied = true,
                                completed = completed,
                            }
                        end)
                    if not progressed then
                        if action_failure then
                            action_failure.error = progress_error
                        end
                        emitActionFailure(world, action_failure)
                    end
                end
            end
        end
    end

    host:registerContentKind("quest", {
        validate = function(definition_value, validator)
            validateQuest(definition_value, validator, host)
        end,
    })
    host.rules:registerAction("start_quest", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "quest"}, path)
            validator:reference(
                action.quest,
                "quest",
                path .. ".quest"
            )
        end,
        execute = function(action, context)
            return quest:start(context.world, action.quest)
        end,
    })
    host.rules:registerCondition("quest_state", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "quest", "state"},
                path
            )
            validator:reference(
                condition.quest,
                "quest",
                path .. ".quest"
            )
            validator:enum(
                condition.state,
                {"inactive", "active", "completed"},
                path .. ".state",
                true
            )
        end,
        evaluate = function(condition)
            local entry = entryFor(condition.quest)
            return (entry and entry.status or "inactive") ==
                condition.state
        end,
    })
    host.rules:registerCondition("quest_objective", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "quest", "objective", "count"},
                path
            )
            local definition_value = validator:reference(
                condition.quest,
                "quest",
                path .. ".quest"
            )
            local objective_id = validator:string(
                condition.objective,
                path .. ".objective",
                true
            )
            if definition_value and objective_id then
                local found = false
                for _, objective in ipairs(
                    definition_value.objectives
                ) do
                    if objective.id == objective_id then
                        found = true
                        break
                    end
                end
                if not found then
                    validator:error(
                        path .. ".objective",
                        "references missing objective '" ..
                            objective_id .. "'"
                    )
                end
            end
            positiveInteger(
                condition.count,
                validator,
                path .. ".count",
                false
            )
        end,
        evaluate = function(condition)
            local entry = entryFor(condition.quest)
            return entry ~= nil and
                (entry.objectives[condition.objective] or 0) >=
                    (condition.count or 1)
        end,
    })

    host:registerWorldInitializer(
        "rpg.quest.events",
        50,
        function(world)
            local event_names = {}
            for _, definition_value in ipairs(host.catalog:all()) do
                if definition_value.kind == "quest" then
                    for _, objective in ipairs(
                        definition_value.objectives
                    ) do
                        event_names[objective.event] = true
                    end
                end
            end
            for _, event_name in ipairs(util.sortedKeys(event_names)) do
                world.events:on(event_name, function(payload)
                    processEvent(world, event_name, payload)
                end)
            end
            return true
        end
    )

    host:registerBootValidator("rpg.quest.session", function()
        for quest_id, entry in pairs(state.quests) do
            local quest_definition = definition(quest_id)
            if not quest_definition then
                return nil, "quest save references missing quest '" ..
                    quest_id .. "'"
            end
            local objectives = {}
            for _, objective in ipairs(
                quest_definition.objectives
            ) do
                objectives[objective.id] = objective.count or 1
            end
            for objective_id, count in pairs(entry.objectives) do
                local goal = objectives[objective_id]
                if not goal then
                    return nil, string.format(
                        "quest save '%s' references missing objective '%s'",
                        quest_id,
                        objective_id
                    )
                end
                if count > goal then
                    return nil, string.format(
                        "quest save '%s' objective '%s' exceeds goal",
                        quest_id,
                        objective_id
                    )
                end
            end
            for objective_id in pairs(objectives) do
                if entry.objectives[objective_id] == nil then
                    return nil, string.format(
                        "quest save '%s' is missing objective '%s'",
                        quest_id,
                        objective_id
                    )
                end
            end
        end
        return true
    end)

    host:registerService("quest", quest)
    host:registerWorldInspector("rpg.quest", function(world)
        local locale = world:service("locale")
        local entries = {}
        for _, quest_id in ipairs(util.sortedKeys(state.quests)) do
            local entry = state.quests[quest_id]
            local definition_value = definition(quest_id)
            local objectives = {}
            for _, objective in ipairs(
                definition_value and
                    definition_value.objectives or {}
            ) do
                objectives[#objectives + 1] = {
                    id = objective.id,
                    event = objective.event,
                    count = entry.objectives[objective.id] or 0,
                    goal = objective.count or 1,
                }
            end
            entries[#entries + 1] = {
                id = quest_id,
                name = definition_value and
                    (locale and definition_value.name_key and
                        locale:text(
                            definition_value.name_key,
                            definition_value.name
                        ) or definition_value.name) or quest_id,
                status = entry.status,
                objectives = objectives,
            }
        end
        return {
            quests = entries,
            quest_count = #entries,
        }
    end)
end

return feature

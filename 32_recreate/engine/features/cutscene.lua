local feature = {
    id = "cutscene",
    requires = {
        "engine.features.world",
        "engine.features.assets",
    },
}

local function validateText(value, validator, path)
    local text = validator:string(value.text, path .. ".text", false)
    local text_key = validator:string(
        value.text_key,
        path .. ".text_key",
        false
    )
    if not text and not text_key then
        validator:error(path .. ".text", "requires text or text_key")
    end
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

local function validateBackground(value, validator, path)
    if value == nil then return end
    local asset = validator:reference(value, "asset", path)
    if asset and asset.asset_type ~= "image" then
        validator:error(path, "cutscene background requires an image asset")
    end
end

local function validateCutscene(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "name_key",
            "background", "skippable", "steps", "on_complete",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    validator:string(definition.name_key, "name_key", false)
    validateBackground(definition.background, validator, "background")
    validator:boolean(definition.skippable, "skippable", false)
    validateActions(
        definition.on_complete,
        validator,
        host,
        "on_complete"
    )

    local steps = validator:array(definition.steps, "steps", true)
    if steps and #steps == 0 then
        validator:error("steps", "must contain at least one step")
    end
    local seen = {}
    for index, step in ipairs(steps or {}) do
        local path = string.format("steps[%d]", index)
        if validator:table(step, path, true) then
            validator:keys(
                step,
                {
                    "id", "speaker", "speaker_key", "text", "text_key",
                    "background", "duration", "actions",
                },
                path
            )
            local id = validator:string(step.id, path .. ".id", true)
            if id and seen[id] then
                validator:error(
                    path .. ".id",
                    "duplicates another cutscene step id"
                )
            elseif id then
                seen[id] = true
            end
            validator:string(
                step.speaker,
                path .. ".speaker",
                false
            )
            validator:string(
                step.speaker_key,
                path .. ".speaker_key",
                false
            )
            validateText(step, validator, path)
            validateBackground(
                step.background,
                validator,
                path .. ".background"
            )
            validator:positive(
                step.duration,
                path .. ".duration",
                false
            )
            validateActions(
                step.actions,
                validator,
                host,
                path .. ".actions"
            )
        end
    end
end

local function stateFor(world)
    local state = world.feature_state.cutscene
    if not state then
        state = {
            active = false,
            step_index = 0,
            remaining = 0,
        }
        world.feature_state.cutscene = state
    end
    return state
end

function feature:register(host)
    for _, input_name in ipairs({"menu_confirm", "menu_cancel"}) do
        assert(
            host.input:hasAction(input_name),
            "cutscene requires input action '" .. input_name .. "'"
        )
    end

    local cutscene = {}

    local function definitionFor(state)
        local definition = state.definition_id and
            host.catalog:get(state.definition_id)
        if definition and definition.kind == "cutscene" then
            return definition
        end
        return nil
    end

    local function contextFor(world, state)
        return {
            source = state.source_id and world:get(state.source_id) or nil,
            target = state.target_id and world:get(state.target_id) or nil,
            interactor = state.interactor_id and
                world:get(state.interactor_id) or nil,
            cutscene_id = state.definition_id,
            cutscene_step = state.step_index,
            world = world,
            events = world.events,
        }
    end

    local function executeActions(world, state, actions, scope)
        local result, action_error, failure =
            world:executeActions(actions, contextFor(world, state))
        if not result then
            return nil, action_error, {
                cutscene_id = state.definition_id,
                step_index = state.step_index,
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
            world.events:emit("cutscene.action_failed", failure)
        end
    end

    local function enterStep(world, state, index)
        local definition = definitionFor(state)
        local step = definition and definition.steps[index]
        if not step then
            return nil, "unknown cutscene step " .. tostring(index)
        end
        state.step_index = index
        state.remaining = step.duration or 0
        local executed, action_error, failure = executeActions(
            world,
            state,
            step.actions,
            "step"
        )
        if not executed then return nil, action_error, failure end
        world.events:emit("cutscene.step_entered", {
            cutscene_id = state.definition_id,
            step_id = step.id,
            step_index = index,
        })
        return true
    end

    local function closeState(state)
        state.active = false
        state.definition_id = nil
        state.step_index = 0
        state.remaining = 0
        state.source_id = nil
        state.target_id = nil
        state.interactor_id = nil
    end

    local function complete(world, state, reason)
        local definition = definitionFor(state)
        if not definition then
            return nil, "active cutscene definition is unavailable"
        end
        local cutscene_id = state.definition_id
        local action_failure
        local result, complete_error = world:transaction(function()
            local executed, action_error, failure = executeActions(
                world,
                state,
                definition.on_complete,
                "complete"
            )
            if not executed then
                action_failure = failure
                return nil, action_error
            end
            closeState(state)
            world.events:emit("cutscene.completed", {
                cutscene_id = cutscene_id,
                reason = reason or "finished",
            })
            return {
                applied = true,
                cutscene_id = cutscene_id,
                reason = reason or "finished",
            }
        end)
        if not result then
            emitActionFailure(world, action_failure)
            return nil, complete_error
        end
        return result
    end

    function cutscene:start(world, cutscene_id, context)
        context = context or {}
        local state = stateFor(world)
        if state.active then
            return nil, "another cutscene is already active"
        end
        local definition = host.catalog:get(cutscene_id)
        if not definition or definition.kind ~= "cutscene" then
            return nil, "unknown cutscene '" .. tostring(cutscene_id) .. "'"
        end
        local action_failure
        local result, start_error = world:transaction(function()
            state.active = true
            state.definition_id = cutscene_id
            state.source_id = context.source and context.source.id or nil
            state.target_id = context.target and context.target.id or nil
            state.interactor_id =
                context.interactor and context.interactor.id or nil
            local entered, enter_error, failure =
                enterStep(world, state, 1)
            if not entered then
                action_failure = failure
                return nil, enter_error
            end
            world.events:emit("cutscene.started", {
                cutscene_id = cutscene_id,
            })
            return {
                applied = true,
                cutscene_id = cutscene_id,
                step_index = 1,
            }
        end)
        if not result then
            emitActionFailure(world, action_failure)
            return nil, start_error
        end
        return result
    end

    function cutscene:advance(world)
        local state = stateFor(world)
        if not state.active then return nil, "no active cutscene" end
        local definition = definitionFor(state)
        if state.step_index >= #definition.steps then
            return complete(world, state, "finished")
        end
        local action_failure
        local result, advance_error = world:transaction(function()
            local entered, enter_error, failure =
                enterStep(world, state, state.step_index + 1)
            if not entered then
                action_failure = failure
                return nil, enter_error
            end
            return {
                applied = true,
                cutscene_id = state.definition_id,
                step_index = state.step_index,
            }
        end)
        if not result then
            emitActionFailure(world, action_failure)
            return nil, advance_error
        end
        return result
    end

    function cutscene:skip(world)
        local state = stateFor(world)
        if not state.active then return nil, "no active cutscene" end
        local definition = definitionFor(state)
        if definition.skippable == false then
            return nil, "cutscene is not skippable"
        end
        local cutscene_id = state.definition_id
        local action_failure
        local result, skip_error = world:transaction(function()
            for index = state.step_index + 1, #definition.steps do
                state.step_index = index
                local executed, action_error, failure = executeActions(
                    world,
                    state,
                    definition.steps[index].actions,
                    "skipped_step"
                )
                if not executed then
                    action_failure = failure
                    return nil, action_error
                end
            end
            local executed, action_error, failure = executeActions(
                world,
                state,
                definition.on_complete,
                "skip_complete"
            )
            if not executed then
                action_failure = failure
                return nil, action_error
            end
            closeState(state)
            world.events:emit("cutscene.skipped", {
                cutscene_id = cutscene_id,
            })
            world.events:emit("cutscene.completed", {
                cutscene_id = cutscene_id,
                reason = "skipped",
            })
            return {
                applied = true,
                cutscene_id = cutscene_id,
                reason = "skipped",
            }
        end)
        if not result then
            emitActionFailure(world, action_failure)
            return nil, skip_error
        end
        return result
    end

    host:registerContentKind("cutscene", {
        validate = function(definition, validator)
            validateCutscene(definition, validator, host)
        end,
    })
    host.rules:registerAction("start_cutscene", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "cutscene"}, path)
            validator:reference(
                action.cutscene,
                "cutscene",
                path .. ".cutscene"
            )
        end,
        execute = function(action, context)
            return cutscene:start(
                context.world,
                action.cutscene,
                context
            )
        end,
    })
    host.rules:registerCondition("cutscene_active", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "cutscene"}, path)
            if condition.cutscene then
                validator:reference(
                    condition.cutscene,
                    "cutscene",
                    path .. ".cutscene"
                )
            end
        end,
        evaluate = function(condition, context)
            local state = context.world and
                stateFor(context.world) or nil
            return state ~= nil and state.active and
                (not condition.cutscene or
                 state.definition_id == condition.cutscene)
        end,
    })

    host:registerWorldInitializer(
        "cutscene",
        80,
        function(world)
            stateFor(world)
            return true
        end
    )
    for _, channel in ipairs({"move", "act", "interact"}) do
        host:registerGate(
            channel,
            "cutscene",
            function(entity, world)
                if entity.tag_set.player and stateFor(world).active then
                    return false, "cutscene"
                end
                return true
            end
        )
    end
    host:registerTimeFilter(
        "cutscene",
        2,
        function(world, dt)
            if stateFor(world).active then return 0 end
            return dt
        end
    )
    host:registerAppController(
        "cutscene.input",
        5,
        function(world, dt)
            local state = stateFor(world)
            if not state.active then return false end
            -- Escape may also be bound to pause. Consume both semantic edges
            -- so the game-flow controller cannot open a second modal.
            local cancel = host.input:consumePressed("menu_cancel")
            host.input:consumePressed("pause")
            if cancel then
                cutscene:skip(world)
                return true
            end
            if host.input:consumePressed("menu_confirm") then
                cutscene:advance(world)
                return true
            end
            if state.remaining > 0 then
                state.remaining = math.max(0, state.remaining - dt)
                if state.remaining == 0 then
                    cutscene:advance(world)
                end
            end
            return true
        end
    )

    local draw_system = {
        id = "cutscene.draw",
        draw_order = 900,
        draw_space = "screen",
    }
    function draw_system:draw(world)
        local state = stateFor(world)
        if not state.active then return end
        local definition = definitionFor(state)
        local step = definition.steps[state.step_index]
        local view = world:view()
        local background = step.background or definition.background
        if background then
            local image = host.assets:image(background)
            local image_width, image_height = image:getDimensions()
            local scale = math.max(
                view.width / image_width,
                view.height / image_height
            )
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(
                image,
                (view.width - image_width * scale) / 2,
                (view.height - image_height * scale) / 2,
                0,
                scale,
                scale
            )
            love.graphics.setColor(0, 0, 0, 0.32)
        else
            love.graphics.setColor(0.01, 0.015, 0.025, 0.76)
        end
        love.graphics.rectangle("fill", 0, 0, view.width, view.height)

        local locale = world:service("locale")
        local speaker = step.speaker_key and locale and
            locale:text(step.speaker_key, step.speaker) or
            step.speaker or ""
        local text = step.text_key and locale and
            locale:text(step.text_key, step.text) or
            step.text or step.text_key
        local panel_x = 46
        local panel_y = view.height - 174
        local panel_width = view.width - 92
        local panel_height = 126
        love.graphics.setColor(0.015, 0.02, 0.035, 0.94)
        love.graphics.rectangle(
            "fill",
            panel_x,
            panel_y,
            panel_width,
            panel_height,
            10,
            10
        )
        love.graphics.setColor(0.75, 0.82, 1, 1)
        love.graphics.rectangle(
            "line",
            panel_x,
            panel_y,
            panel_width,
            panel_height,
            10,
            10
        )
        if speaker ~= "" then
            love.graphics.setColor(1, 0.82, 0.3, 1)
            love.graphics.print(speaker, panel_x + 18, panel_y + 14)
        end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(
            text,
            panel_x + 18,
            panel_y + (speaker ~= "" and 42 or 24),
            panel_width - 36
        )
        love.graphics.setColor(0.72, 0.78, 0.88, 1)
        local continue_label = locale and locale:text(
            "ui.cutscene.continue",
            "Enter/Space Continue"
        ) or "Enter/Space Continue"
        local skip_label = locale and locale:text(
            "ui.cutscene.skip",
            "Esc Skip"
        ) or "Esc Skip"
        local footer = string.format(
            "%d / %d    %s%s",
            state.step_index,
            #definition.steps,
            continue_label,
            definition.skippable == false and "" or
                "    " .. skip_label
        )
        love.graphics.printf(
            footer,
            panel_x + 18,
            panel_y + panel_height - 28,
            panel_width - 36,
            "right"
        )
    end

    host:registerService("cutscene", cutscene)
    host:registerWorldInspector("cutscene", function(world)
        local state = stateFor(world)
        local result = {
            active = state.active,
            cutscene_id = state.definition_id,
            step_index = state.step_index,
            remaining = state.remaining,
        }
        if state.active then
            local definition = definitionFor(state)
            local step = definition.steps[state.step_index]
            local locale = world:service("locale")
            result.step_id = step.id
            result.step_count = #definition.steps
            result.skippable = definition.skippable ~= false
            result.speaker = step.speaker_key and locale and
                locale:text(step.speaker_key, step.speaker) or
                step.speaker
            result.text = step.text_key and locale and
                locale:text(step.text_key, step.text) or
                step.text or step.text_key
            result.background = step.background or definition.background
        end
        return {cutscene = result}
    end)
    host:registerSystem(draw_system)
end

return feature

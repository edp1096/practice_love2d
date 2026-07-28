local util = require "engine.core.util"

local feature = {
    id = "rpg.dialogue",
    requires = {
        "engine.features.rpg.locale",
        "engine.features.control",
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

local function validateTextFields(value, validator, path)
    local text = validator:string(value.text, path .. ".text", false)
    local text_key = validator:string(
        value.text_key,
        path .. ".text_key",
        false
    )
    if not text and not text_key then
        validator:error(
            path .. ".text",
            "requires text or text_key"
        )
    end
end

local function validateDialogue(definition, validator, host)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "name_key",
            "start", "nodes",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    validator:string(definition.name_key, "name_key", false)
    local start = validator:string(definition.start, "start", true)
    local nodes = validator:table(definition.nodes, "nodes", true)
    local node_count = 0
    for node_id, node in pairs(nodes or {}) do
        node_count = node_count + 1
        local path = "nodes." .. tostring(node_id)
        if type(node_id) ~= "string" or node_id == "" then
            validator:error(
                "nodes",
                "node ids must be non-empty strings"
            )
        elseif validator:table(node, path, true) then
            validator:keys(
                node,
                {
                    "speaker", "speaker_key", "text", "text_key",
                    "next", "choices", "actions",
                },
                path
            )
            validator:string(
                node.speaker,
                path .. ".speaker",
                false
            )
            validator:string(
                node.speaker_key,
                path .. ".speaker_key",
                false
            )
            validateTextFields(node, validator, path)
            validator:string(node.next, path .. ".next", false)
            validateActions(
                node.actions,
                validator,
                host,
                path .. ".actions"
            )
            local choices = validator:array(
                node.choices,
                path .. ".choices",
                false
            )
            if choices and #choices == 0 then
                validator:error(
                    path .. ".choices",
                    "must not be empty"
                )
            end
            if choices and node.next then
                validator:error(
                    path,
                    "must use either next or choices, not both"
                )
            end
            local choice_ids = {}
            for index, choice in ipairs(choices or {}) do
                local choice_path = string.format(
                    "%s.choices[%d]",
                    path,
                    index
                )
                if validator:table(choice, choice_path, true) then
                    validator:keys(
                        choice,
                        {
                            "id", "text", "text_key", "next",
                            "condition", "actions",
                        },
                        choice_path
                    )
                    local choice_id = validator:string(
                        choice.id,
                        choice_path .. ".id",
                        true
                    )
                    if choice_id and choice_ids[choice_id] then
                        validator:error(
                            choice_path .. ".id",
                            "duplicates another choice id"
                        )
                    elseif choice_id then
                        choice_ids[choice_id] = true
                    end
                    validateTextFields(
                        choice,
                        validator,
                        choice_path
                    )
                    validator:string(
                        choice.next,
                        choice_path .. ".next",
                        false
                    )
                    if choice.condition then
                        host.rules:validateCondition(
                            choice.condition,
                            validator,
                            choice_path .. ".condition"
                        )
                    end
                    validateActions(
                        choice.actions,
                        validator,
                        host,
                        choice_path .. ".actions"
                    )
                end
            end
        end
    end
    if nodes and node_count == 0 then
        validator:error("nodes", "must not be empty")
    end
    if start and nodes and not nodes[start] then
        validator:error("start", "references missing node '" .. start .. "'")
    end
    for node_id, node in pairs(nodes or {}) do
        if type(node_id) == "string" and type(node) == "table" then
            if node.next and not nodes[node.next] then
                validator:error(
                    "nodes." .. node_id .. ".next",
                    "references missing node '" .. node.next .. "'"
                )
            end
            for index, choice in ipairs(node.choices or {}) do
                if type(choice) == "table" and choice.next and
                   not nodes[choice.next] then
                    validator:error(
                        string.format(
                            "nodes.%s.choices[%d].next",
                            node_id,
                            index
                        ),
                        "references missing node '" ..
                            choice.next .. "'"
                    )
                end
            end
        end
    end
end

local function stateFor(world)
    local state = world.feature_state.dialogue
    if not state then
        state = {
            active = false,
            selected = 1,
            visible_choices = {},
        }
        world.feature_state.dialogue = state
    end
    return state
end

function feature:register(host)
    for _, input_name in ipairs({
        "menu_up",
        "menu_down",
        "menu_confirm",
        "menu_cancel",
    }) do
        assert(
            host.input:hasAction(input_name),
            "rpg.dialogue requires input action '" .. input_name .. "'"
        )
    end
    local dialogue = {}

    local function definitionFor(state)
        local definition = state.definition_id and
            host.catalog:get(state.definition_id)
        if definition and definition.kind == "dialogue" then
            return definition
        end
        return nil
    end

    local function contextFor(world, state)
        return {
            source = state.speaker_entity_id and
                world:get(state.speaker_entity_id) or nil,
            target = state.interactor_id and
                world:get(state.interactor_id) or nil,
            interactor = state.interactor_id and
                world:get(state.interactor_id) or nil,
            speaker = state.speaker_entity_id and
                world:get(state.speaker_entity_id) or nil,
            dialogue_id = state.definition_id,
            node_id = state.node_id,
            world = world,
            events = world.events,
        }
    end

    local function executeActions(world, state, actions, scope)
        local context = contextFor(world, state)
        for index, action in ipairs(actions or {}) do
            local result, action_error = world:execute(action, context)
            if result == nil or result == false then
                world.events:emit("dialogue.action_failed", {
                    dialogue_id = state.definition_id,
                    node_id = state.node_id,
                    scope = scope,
                    action_index = index,
                    error = action_error,
                })
                return nil, action_error
            end
            if type(result) == "table" and result.stop_effects then
                break
            end
        end
        return true
    end

    local function refreshChoices(world, state)
        state.visible_choices = {}
        local definition = definitionFor(state)
        local node = definition and definition.nodes[state.node_id]
        local context = contextFor(world, state)
        for _, choice in ipairs(node and node.choices or {}) do
            if not choice.condition or
               host.rules:evaluate(choice.condition, context) then
                state.visible_choices[
                    #state.visible_choices + 1
                ] = choice
            end
        end
        state.selected = util.clamp(
            state.selected or 1,
            1,
            math.max(1, #state.visible_choices)
        )
    end

    local function enterNode(world, state, node_id)
        local definition = definitionFor(state)
        local node = definition and definition.nodes[node_id]
        if not node then
            return nil, "unknown dialogue node '" .. tostring(node_id) .. "'"
        end
        state.node_id = node_id
        state.selected = 1
        local executed, action_error = executeActions(
            world,
            state,
            node.actions,
            "node"
        )
        if not executed then return nil, action_error end
        refreshChoices(world, state)
        world.events:emit("dialogue.node_entered", {
            dialogue_id = state.definition_id,
            node_id = node_id,
        })
        return true
    end

    function dialogue:start(
        world,
        dialogue_id,
        interactor,
        speaker
    )
        local state = stateFor(world)
        if state.active then
            return nil, "another dialogue is already active"
        end
        local definition = host.catalog:get(dialogue_id)
        if not definition or definition.kind ~= "dialogue" then
            return nil, "unknown dialogue '" .. tostring(dialogue_id) .. "'"
        end
        state.active = true
        state.definition_id = dialogue_id
        state.interactor_id = interactor and interactor.id or nil
        state.speaker_entity_id = speaker and speaker.id or nil
        local entered, enter_error =
            enterNode(world, state, definition.start)
        if not entered then
            state.active = false
            return nil, enter_error
        end
        world.events:emit("dialogue.started", {
            dialogue_id = dialogue_id,
            interactor_id = state.interactor_id,
            speaker_entity_id = state.speaker_entity_id,
        })
        return {
            applied = true,
            dialogue_id = dialogue_id,
            node_id = state.node_id,
        }
    end

    function dialogue:close(world, reason)
        local state = stateFor(world)
        if not state.active then
            return {applied = false}
        end
        local dialogue_id = state.definition_id
        state.active = false
        state.definition_id = nil
        state.node_id = nil
        state.interactor_id = nil
        state.speaker_entity_id = nil
        state.visible_choices = {}
        state.selected = 1
        world.events:emit("dialogue.closed", {
            dialogue_id = dialogue_id,
            reason = reason or "closed",
        })
        return {
            applied = true,
            dialogue_id = dialogue_id,
        }
    end

    function dialogue:advance(world)
        local state = stateFor(world)
        if not state.active then return nil, "no active dialogue" end
        local definition = definitionFor(state)
        local node = definition.nodes[state.node_id]
        if node.choices then
            return nil, "dialogue node requires a choice"
        end
        if node.next then
            local entered, enter_error =
                enterNode(world, state, node.next)
            if not entered then return nil, enter_error end
            return {
                applied = true,
                node_id = state.node_id,
            }
        end
        return self:close(world, "finished")
    end

    function dialogue:choose(world, selector)
        local state = stateFor(world)
        if not state.active then return nil, "no active dialogue" end
        refreshChoices(world, state)
        local choice
        if type(selector) == "number" then
            choice = state.visible_choices[selector]
        else
            for _, candidate in ipairs(state.visible_choices) do
                if candidate.id == selector then choice = candidate end
            end
        end
        if not choice then
            return nil, "unknown visible dialogue choice '" ..
                tostring(selector) .. "'"
        end
        local choice_id = choice.id
        local executed, action_error = executeActions(
            world,
            state,
            choice.actions,
            "choice"
        )
        if not executed then return nil, action_error end
        world.events:emit("dialogue.choice_selected", {
            dialogue_id = state.definition_id,
            node_id = state.node_id,
            choice_id = choice_id,
        })
        if choice.next then
            local entered, enter_error =
                enterNode(world, state, choice.next)
            if not entered then return nil, enter_error end
            return {
                applied = true,
                choice_id = choice_id,
                node_id = state.node_id,
            }
        end
        local result = self:close(world, "choice")
        result.choice_id = choice_id
        return result
    end

    host:registerContentKind("dialogue", {
        validate = function(definition, validator)
            validateDialogue(definition, validator, host)
        end,
    })
    host.rules:registerAction("start_dialogue", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "dialogue"}, path)
            validator:reference(
                action.dialogue,
                "dialogue",
                path .. ".dialogue"
            )
        end,
        execute = function(action, context)
            local interactor = context.interactor or context.source or
                context.target or context.world:findByTag("player")[1]
            local speaker = context.interactable or
                (context.target ~= interactor and context.target or nil)
            return dialogue:start(
                context.world,
                action.dialogue,
                interactor,
                speaker
            )
        end,
    })
    host.rules:registerAction("close_dialogue", {
        validate = function(action, validator, path)
            validator:keys(action, {"type"}, path)
        end,
        execute = function(_, context)
            return dialogue:close(context.world, "action")
        end,
    })
    host.rules:registerCondition("dialogue_active", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "dialogue"},
                path
            )
            if condition.dialogue then
                validator:reference(
                    condition.dialogue,
                    "dialogue",
                    path .. ".dialogue"
                )
            end
        end,
        evaluate = function(condition, context)
            local state = context.world and
                stateFor(context.world) or nil
            return state ~= nil and state.active and
                (not condition.dialogue or
                 state.definition_id == condition.dialogue)
        end,
    })

    host:registerWorldInitializer(
        "rpg.dialogue",
        90,
        function(world)
            stateFor(world)
            return true
        end
    )
    for _, channel in ipairs({"move", "act", "interact"}) do
        host:registerGate(
            channel,
            "rpg.dialogue",
            function(entity, world)
                local state = stateFor(world)
                if state.active and entity.tag_set.player then
                    return false, "dialogue"
                end
                return true
            end
        )
    end

    local input_system = {
        id = "rpg.dialogue.input",
        phase = "input",
        order = 100,
    }
    function input_system:update(world)
        local state = stateFor(world)
        if not state.active then return end
        local input = host.input
        if input:wasPressed("menu_cancel") then
            dialogue:close(world, "cancelled")
            return
        end
        refreshChoices(world, state)
        if #state.visible_choices > 0 then
            if input:wasPressed("menu_up") then
                state.selected = state.selected - 1
                if state.selected < 1 then
                    state.selected = #state.visible_choices
                end
            elseif input:wasPressed("menu_down") then
                state.selected = state.selected + 1
                if state.selected > #state.visible_choices then
                    state.selected = 1
                end
            end
        end
        if input:wasPressed("menu_confirm") then
            if #state.visible_choices > 0 then
                dialogue:choose(world, state.selected)
            else
                dialogue:advance(world)
            end
        end
    end

    local draw_system = {
        id = "rpg.dialogue.draw",
        draw_order = 300,
        draw_space = "screen",
    }
    function draw_system:draw(world)
        local state = stateFor(world)
        if not state.active then return end
        local definition = definitionFor(state)
        local node = definition.nodes[state.node_id]
        local locale = world:service("locale")
        local speaker = node.speaker_key and
            locale:text(node.speaker_key, node.speaker) or
            node.speaker or ""
        local text = node.text_key and
            locale:text(node.text_key, node.text) or node.text
        local view = world:view()
        local height = #state.visible_choices > 0 and 190 or 132
        local x, y = 36, view.height - height - 58
        local width = view.width - 72
        love.graphics.setColor(0.015, 0.02, 0.035, 0.96)
        love.graphics.rectangle("fill", x, y, width, height, 10, 10)
        love.graphics.setColor(0.35, 0.8, 1, 1)
        love.graphics.rectangle("line", x, y, width, height, 10, 10)
        if speaker ~= "" then
            love.graphics.setColor(1, 0.82, 0.3, 1)
            love.graphics.print(speaker, x + 18, y + 14)
        end
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(
            text,
            x + 18,
            y + 40,
            width - 36
        )
        for index, choice in ipairs(state.visible_choices) do
            local choice_text = choice.text_key and
                locale:text(choice.text_key, choice.text) or choice.text
            love.graphics.setColor(
                index == state.selected and 1 or 0.72,
                index == state.selected and 0.85 or 0.76,
                index == state.selected and 0.3 or 0.84,
                1
            )
            love.graphics.print(
                (index == state.selected and "> " or "  ") ..
                    choice_text,
                x + 28,
                y + 88 + (index - 1) * 25
            )
        end
    end

    host:registerService("dialogue", dialogue)
    host:registerWorldInspector("rpg.dialogue", function(world)
        local state = stateFor(world)
        local result = {
            active = state.active,
            dialogue_id = state.definition_id,
            node_id = state.node_id,
            interactor_id = state.interactor_id,
            speaker_entity_id = state.speaker_entity_id,
            selected = state.selected,
            choices = {},
        }
        if state.active then
            refreshChoices(world, state)
            local definition = definitionFor(state)
            local node = definition.nodes[state.node_id]
            local locale = world:service("locale")
            result.speaker = node.speaker_key and
                locale:text(node.speaker_key, node.speaker) or
                node.speaker
            result.text = node.text_key and
                locale:text(node.text_key, node.text) or node.text
            for _, choice in ipairs(state.visible_choices) do
                result.choices[#result.choices + 1] = {
                    id = choice.id,
                    text = choice.text_key and
                        locale:text(choice.text_key, choice.text) or
                        choice.text,
                }
            end
        end
        return {dialogue = result}
    end)
    host:registerSystem(input_system)
    host:registerSystem(draw_system)
end

return feature

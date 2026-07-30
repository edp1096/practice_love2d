local util = require "engine.core.util"
local EventPages = require "engine.core.event_pages"

local feature = {
    id = "rpg.interaction",
    requires = {"engine.features.control"},
}

local function validateActions(actions, validator, host, path)
    actions = validator:array(actions, path, true)
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
end

local function validateInput(host, value, validator, path)
    local input = validator:string(value, path, false)
    if input and not host.input:hasAction(input) then
        validator:error(
            path,
            "references missing input action '" .. input .. "'"
        )
    end
end

local function validatePage(page, validator, host, path)
    validator:keys(
        page,
        {
            "id", "condition", "input", "range",
            "prompt", "prompt_key", "actions",
        },
        path
    )
    validateInput(host, page.input, validator, path .. ".input")
    validator:positive(page.range, path .. ".range", false)
    validator:string(page.prompt, path .. ".prompt", false)
    validator:string(
        page.prompt_key,
        path .. ".prompt_key",
        false
    )
    validateActions(
        page.actions,
        validator,
        host,
        path .. ".actions"
    )
end

local function distanceSquared(left, right)
    local left_transform = left.components.transform
    local right_transform = right.components.transform
    local dx = left_transform.x - right_transform.x
    local dy = left_transform.y - right_transform.y
    return dx * dx + dy * dy
end

local function stateFor(world)
    local state = world.feature_state.interaction
    if not state then
        state = {
            target_id = nil,
            prompt = nil,
            page_id = nil,
        }
        world.feature_state.interaction = state
    end
    return state
end

local function clearState(state)
    state.target_id = nil
    state.prompt = nil
    state.prompt_key = nil
    state.page_id = nil
end

local function activeConfig(world, player, entity)
    local config = entity.components["rpg.interactable"]
    local context = {
        source = player,
        target = entity,
        interactor = player,
        interactable = entity,
        world = world,
        events = world.events,
    }
    if config.condition and
       not world.host.rules:evaluate(config.condition, context) then
        return nil
    end

    local page
    if #config.pages > 0 then
        page = EventPages.select(
            world.host.rules,
            config.pages,
            context
        )
        if not page then return nil end
    end
    return {
        input = page and page.input or config.input,
        range = page and page.range or config.range,
        prompt = page and page.prompt or config.prompt,
        prompt_key = page and page.prompt_key or config.prompt_key,
        actions = page and page.actions or config.actions,
        page_id = page and page.id or nil,
    }, context
end

local interaction_system = {
    id = "rpg.interaction.input",
    phase = "input",
    order = 80,
}

function interaction_system:update(world)
    local state = stateFor(world)
    clearState(state)
    local player = world:findByTag("player")[1]
    if not player or player.dead or
       not world:allows(player, "interact") then
        return
    end

    local nearest
    local nearest_distance
    local nearest_config
    local nearest_context
    for _, entity in ipairs(
        world:query("transform", "rpg.interactable")
    ) do
        if entity ~= player and not entity.dead then
            local config, context =
                activeConfig(world, player, entity)
            local distance = config and
                distanceSquared(player, entity) or nil
            if config and distance <= config.range * config.range then
                if not nearest_distance or
                    distance < nearest_distance or
                    (distance == nearest_distance and
                     entity.id < nearest.id) then
                    nearest = entity
                    nearest_distance = distance
                    nearest_config = config
                    nearest_context = context
                end
            end
        end
    end
    if not nearest then return end

    local config = nearest_config
    state.target_id = nearest.id
    state.prompt = config.prompt
    state.prompt_key = config.prompt_key
    state.page_id = config.page_id
    if not world.host.input:wasPressed(config.input) then return end

    local context = nearest_context
    world.events:emit("interaction.started", {
        source_id = player.id,
        target_id = nearest.id,
        page_id = config.page_id,
    })
    local result, action_error, failure =
        world:executeActions(config.actions, context)
    if not result then
        world.events:emit("interaction.action_failed", {
            source_id = player.id,
            target_id = nearest.id,
            page_id = config.page_id,
            action_index = failure and failure.index or nil,
            action_type = failure and failure.action.type or nil,
            error = action_error,
        })
        return
    end
    world.events:emit("interaction.completed", {
        source_id = player.id,
        target_id = nearest.id,
        page_id = config.page_id,
    })
    if not world:allows(player, "interact") then
        clearState(state)
    end
end

local prompt_system = {
    id = "rpg.interaction.prompt",
    draw_order = 240,
    draw_space = "screen",
}

function prompt_system:draw(world)
    local state = stateFor(world)
    if not state.target_id then return end
    local player = world:findByTag("player")[1]
    if not player or not world:allows(player, "interact") then return end
    local locale = world:service("locale")
    local prompt = state.prompt_key and locale and
        locale:text(state.prompt_key, state.prompt) or
        state.prompt or "Interact"
    local view = world:view()
    love.graphics.setColor(0.02, 0.025, 0.04, 0.9)
    love.graphics.rectangle(
        "fill",
        view.width / 2 - 110,
        view.height - 70,
        220,
        32,
        6,
        6
    )
    love.graphics.setColor(1, 0.9, 0.45, 1)
    love.graphics.printf(
        "[E] " .. prompt,
        view.width / 2 - 100,
        view.height - 62,
        200,
        "center"
    )
end

function feature:register(host)
    host:registerComponent("rpg.interactable", {
        validate = function(config, validator, path)
            if not validator:table(config, path, true) then return end
            validator:keys(
                config,
                {
                    "input", "range", "prompt", "prompt_key",
                    "condition", "actions", "pages",
                },
                path
            )
            local input = config.input or "interact"
            if type(input) == "string" and
               not host.input:hasAction(input) then
                validator:error(
                    path .. ".input",
                    "references missing input action '" .. input .. "'"
                )
            else
                validator:string(
                    config.input,
                    path .. ".input",
                    false
                )
            end
            validator:positive(
                config.range,
                path .. ".range",
                false
            )
            validator:string(
                config.prompt,
                path .. ".prompt",
                false
            )
            validator:string(
                config.prompt_key,
                path .. ".prompt_key",
                false
            )
            if config.condition then
                host.rules:validateCondition(
                    config.condition,
                    validator,
                    path .. ".condition"
                )
            end
            local pages = EventPages.validate(
                host,
                config.pages,
                validator,
                path .. ".pages",
                function(page, current_validator, page_path)
                    validatePage(
                        page,
                        current_validator,
                        host,
                        page_path
                    )
                end
            )
            if not pages then
                validateActions(
                    config.actions,
                    validator,
                    host,
                    path .. ".actions"
                )
            elseif config.actions then
                validateActions(
                    config.actions,
                    validator,
                    host,
                    path .. ".actions"
                )
            end
        end,
        create = function(config)
            return {
                input = config.input or "interact",
                range = config.range or 56,
                prompt = config.prompt,
                prompt_key = config.prompt_key,
                condition = config.condition and
                    util.deepCopy(config.condition) or nil,
                actions = util.deepCopy(config.actions or {}),
                pages = util.deepCopy(config.pages or {}),
            }
        end,
    })
    host:registerWorldInitializer(
        "rpg.interaction",
        100,
        function(world)
            stateFor(world)
            return true
        end
    )
    host:registerWorldInspector("rpg.interaction", function(world)
        local state = stateFor(world)
        return {
            interaction = {
                active = state.target_id ~= nil,
                target_id = state.target_id,
                prompt = state.prompt,
                prompt_key = state.prompt_key,
                page_id = state.page_id,
            },
        }
    end)
    host:registerSystem(interaction_system)
    host:registerSystem(prompt_system)
end

return feature

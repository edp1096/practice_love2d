local util = require "engine.core.util"

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
        }
        world.feature_state.interaction = state
    end
    return state
end

local function clearState(state)
    state.target_id = nil
    state.prompt = nil
    state.prompt_key = nil
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
    for _, entity in ipairs(
        world:query("transform", "rpg.interactable")
    ) do
        if entity ~= player and not entity.dead then
            local config = entity.components["rpg.interactable"]
            local distance = distanceSquared(player, entity)
            if distance <= config.range * config.range then
                local context = {
                    source = player,
                    target = entity,
                    interactor = player,
                    interactable = entity,
                    world = world,
                    events = world.events,
                }
                if (not config.condition or
                    world.host.rules:evaluate(
                        config.condition,
                        context
                    )) and
                   (not nearest_distance or
                    distance < nearest_distance or
                    (distance == nearest_distance and
                     entity.id < nearest.id)) then
                    nearest = entity
                    nearest_distance = distance
                end
            end
        end
    end
    if not nearest then return end

    local config = nearest.components["rpg.interactable"]
    state.target_id = nearest.id
    state.prompt = config.prompt
    state.prompt_key = config.prompt_key
    if not world.host.input:wasPressed(config.input) then return end

    local context = {
        source = player,
        target = nearest,
        interactor = player,
        interactable = nearest,
        world = world,
        events = world.events,
    }
    world.events:emit("interaction.started", {
        source_id = player.id,
        target_id = nearest.id,
    })
    for index, action in ipairs(config.actions) do
        local result, action_error = world:execute(action, context)
        if result == nil or result == false then
            world.events:emit("interaction.action_failed", {
                source_id = player.id,
                target_id = nearest.id,
                action_index = index,
                error = action_error,
            })
            return
        end
        if type(result) == "table" and result.stop_effects then
            break
        end
    end
    world.events:emit("interaction.completed", {
        source_id = player.id,
        target_id = nearest.id,
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
                    "condition", "actions",
                },
                path
            )
            local input = validator:string(
                config.input,
                path .. ".input",
                false
            ) or "interact"
            if not host.input:hasAction(input) then
                validator:error(
                    path .. ".input",
                    "references missing input action '" .. input .. "'"
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
            validateActions(
                config.actions,
                validator,
                host,
                path .. ".actions"
            )
        end,
        create = function(config)
            return {
                input = config.input or "interact",
                range = config.range or 56,
                prompt = config.prompt,
                prompt_key = config.prompt_key,
                condition = config.condition and
                    util.deepCopy(config.condition) or nil,
                actions = util.deepCopy(config.actions),
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
            },
        }
    end)
    host:registerSystem(interaction_system)
    host:registerSystem(prompt_system)
end

return feature

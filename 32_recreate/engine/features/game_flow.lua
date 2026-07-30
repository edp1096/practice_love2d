local Schema = require "engine.runtime.session_schema"
local util = require "engine.core.util"

local feature = {
    id = "game_flow",
    requires = {
        "engine.features.accessibility",
        "engine.features.session",
        "engine.features.world",
    },
}

local modes = {
    title = true,
    playing = true,
    paused = true,
    gameover = true,
    ending = true,
}

local function validateScreen(value, path)
    if value == nil then return true end
    if type(value) ~= "table" then
        return nil, path .. " must be a table"
    end
    local allowed = {
        heading = true,
        heading_key = true,
        message = true,
        message_key = true,
    }
    for key, field in pairs(value) do
        if not allowed[key] then
            return nil, path .. " contains unknown field '" ..
                tostring(key) .. "'"
        end
        if type(field) ~= "string" or field == "" then
            return nil, path .. "." .. tostring(key) ..
                " must be a non-empty string"
        end
    end
    return true
end

local function validateConfig(host, config)
    if type(config) ~= "table" then
        return nil, "game manifest flow must be a table"
    end
    local allowed = {
        save_slot = true,
        start_stage = true,
        start_spawn = true,
        title = true,
        game_over = true,
        ending = true,
    }
    for key in pairs(config) do
        if not allowed[key] then
            return nil, "game manifest flow contains unknown field '" ..
                tostring(key) .. "'"
        end
    end
    if type(config.save_slot) ~= "string" or
       #config.save_slot < 1 or #config.save_slot > 64 or
       not config.save_slot:match("^[a-z0-9_-]+$") then
        return nil, "game manifest flow.save_slot must use 1-64 " ..
            "lowercase letters, digits, underscores, or hyphens"
    end
    if type(config.start_stage) ~= "string" or
       config.start_stage == "" then
        return nil, "game manifest flow.start_stage is required"
    end
    local stage = host.catalog:get(config.start_stage)
    if not stage or stage.kind ~= "stage" then
        return nil, "game manifest flow.start_stage references missing " ..
            "stage '" .. tostring(config.start_stage) .. "'"
    end
    if config.start_spawn ~= nil then
        if type(config.start_spawn) ~= "string" or
           config.start_spawn == "" then
            return nil, "game manifest flow.start_spawn must be a " ..
                "non-empty string"
        end
        local found = false
        for _, point in ipairs(stage.spawn_points or {}) do
            if point.id == config.start_spawn then
                found = true
                break
            end
        end
        if not found then
            return nil, string.format(
                "game manifest flow.start_stage '%s' has no spawn " ..
                    "point '%s'",
                config.start_stage,
                config.start_spawn
            )
        end
    end
    for name, value in pairs({
        title = config.title,
        game_over = config.game_over,
        ending = config.ending,
    }) do
        local valid, screen_error =
            validateScreen(value, "game manifest flow." .. name)
        if not valid then return nil, screen_error end
    end
    return true
end

local function screenText(world, screen, field, fallback)
    screen = screen or {}
    local direct = screen[field]
    local key = screen[field .. "_key"]
    local locale = world:service("locale")
    if key and locale then return locale:text(key, direct or fallback) end
    return direct or fallback
end

function feature:register(host)
    local config = host.manifest.flow
    local input = host.input
    for _, action in ipairs({
        "menu_up",
        "menu_down",
        "menu_confirm",
        "menu_cancel",
        "pause",
    }) do
        assert(
            input:hasAction(action),
            "game_flow requires input action '" .. action .. "'"
        )
    end

    local session = host.services.session
    local progress = session:registerSection("game.flow", {
        version = 1,
        defaults = {
            started = false,
            completed = false,
        },
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "game.flow",
                {"started", "completed"},
                {"started", "completed"}
            )
            if not valid then return nil, value_error end
            if type(value.started) ~= "boolean" then
                return nil, "game.flow.started must be a boolean"
            end
            if type(value.completed) ~= "boolean" then
                return nil, "game.flow.completed must be a boolean"
            end
            if value.completed and not value.started then
                return nil, "game.flow.completed requires started"
            end
            return true
        end,
    })

    local flow = {}

    local function stateFor(world)
        local state = world.feature_state.game_flow
        if not state then
            local mode = "title"
            if progress.completed then
                mode = "ending"
            elseif progress.started then
                mode = "playing"
            end
            state = {
                mode = mode,
                panel = nil,
                selected = 1,
                notice = nil,
                notice_success = false,
                notice_remaining = 0,
            }
            world.feature_state.game_flow = state
        end
        return state
    end

    local function hasSave()
        return host.filesystem:info(
            "saves/" .. config.save_slot .. ".lua"
        ) ~= nil
    end

    local function optionsFor(world)
        local state = stateFor(world)
        local options = {}
        local function add(id, key, fallback)
            local locale = world:service("locale")
            options[#options + 1] = {
                id = id,
                label = locale and locale:text(key, fallback) or fallback,
            }
        end
        if state.panel == "accessibility" then
            local accessibility = world:service("accessibility")
            local settings = accessibility:inspect()
            local locale = world:service("locale")
            local function value(key, fallback)
                return locale and locale:text(key, fallback) or fallback
            end
            add(
                "accessibility_motion",
                "accessibility.motion",
                "Camera motion"
            )
            options[#options].label = options[#options].label .. ": " ..
                value(
                    "accessibility.motion." .. settings.motion,
                    settings.motion
                )
            add(
                "accessibility_hit_flash",
                "accessibility.hit_flash",
                "Hit flash"
            )
            options[#options].label = options[#options].label .. ": " ..
                value(
                    settings.hit_flash and
                        "accessibility.value.on" or
                        "accessibility.value.off",
                    settings.hit_flash and "On" or "Off"
                )
            add(
                "accessibility_notice_duration",
                "accessibility.notice_duration",
                "Message duration"
            )
            options[#options].label = options[#options].label .. ": " ..
                value(
                    "accessibility.notice_duration." ..
                        settings.notice_duration,
                    settings.notice_duration
                )
            add("accessibility_back", "flow.menu.back", "Back")
            state.selected = util.clamp(state.selected, 1, #options)
            return options
        end
        if state.mode == "title" then
            add("new_game", "flow.menu.new_game", "New Game")
            if hasSave() then
                add("continue", "flow.menu.continue", "Continue")
            end
            add(
                "accessibility",
                "flow.menu.accessibility",
                "Accessibility"
            )
            add("quit", "flow.menu.quit", "Quit")
        elseif state.mode == "paused" then
            add("resume", "flow.menu.resume", "Resume")
            add("save", "flow.menu.save", "Save")
            add(
                "accessibility",
                "flow.menu.accessibility",
                "Accessibility"
            )
            add("title", "flow.menu.title", "Return to Title")
        elseif state.mode == "gameover" then
            add("retry", "flow.menu.retry", "Retry")
            if hasSave() then
                add("continue", "flow.menu.continue", "Continue")
            end
            add("title", "flow.menu.title", "Return to Title")
        elseif state.mode == "ending" then
            add("new_game", "flow.menu.new_game", "New Game")
            add("title", "flow.menu.title", "Return to Title")
        end
        state.selected = util.clamp(
            state.selected,
            1,
            math.max(1, #options)
        )
        return options
    end

    function flow:prepareNewGame()
        progress.started = true
        progress.completed = false
        return true
    end

    function flow:mode(world)
        return stateFor(world).mode
    end

    function flow:notify(world, message, success)
        local state = stateFor(world)
        state.notice = tostring(message)
        state.notice_success = success == true
        state.notice_remaining = 3
    end

    local function setMode(world, mode)
        assert(modes[mode], "unknown game flow mode")
        local state = stateFor(world)
        if state.mode == mode then return false end
        local previous = state.mode
        state.mode = mode
        state.panel = nil
        state.selected = 1
        state.notice = nil
        state.notice_remaining = 0
        world.events:emit("game.flow_changed", {
            mode = mode,
            previous = previous,
        })
        return true
    end

    local function activate(world, option, direction)
        local state = stateFor(world)
        local keep_selection = false
        if option.id == "new_game" then
            world:request({
                type = "new_game",
                stage_id = config.start_stage,
                spawn_id = config.start_spawn,
            })
        elseif option.id == "continue" then
            world:request({
                type = "load_game",
                slot = config.save_slot,
            })
        elseif option.id == "quit" then
            world:request({type = "quit"})
        elseif option.id == "resume" then
            setMode(world, "playing")
        elseif option.id == "save" then
            world:request({
                type = "save_game",
                slot = config.save_slot,
            })
        elseif option.id == "title" then
            world:request({type = "return_to_title"})
        elseif option.id == "retry" then
            world:request({type = "restart_stage"})
        elseif option.id == "accessibility" then
            state.panel = "accessibility"
        elseif option.id == "accessibility_back" then
            state.panel = nil
        elseif option.id == "accessibility_motion" then
            world:service("accessibility"):cycle(
                "motion",
                direction or 1
            )
            keep_selection = true
        elseif option.id == "accessibility_hit_flash" then
            world:service("accessibility"):cycle("hit_flash", 1)
            keep_selection = true
        elseif option.id == "accessibility_notice_duration" then
            world:service("accessibility"):cycle(
                "notice_duration",
                direction or 1
            )
            keep_selection = true
        end
        if not keep_selection then state.selected = 1 end
    end

    host:registerBootValidator("game_flow", function()
        return validateConfig(host, config)
    end)
    host:registerService("game_flow", flow)
    host.rules:registerAction("finish_game", {
        validate = function(action, validator, path)
            validator:keys(action, {"type"}, path)
        end,
        execute = function(_, context)
            progress.started = true
            progress.completed = true
            setMode(context.world, "ending")
            context.world.events:emit("game.completed", {
                stage_id = context.world.stage.id,
            })
            return {applied = true}
        end,
    })
    host.rules:registerAction("save_game", {
        validate = function(action, validator, path)
            validator:keys(action, {"type"}, path)
        end,
        execute = function(_, context)
            context.world:request({
                type = "save_game",
                slot = config.save_slot,
            })
            return {applied = true, slot = config.save_slot}
        end,
    })
    host.rules:registerCondition("game_flow_state", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "state"}, path)
            validator:enum(
                condition.state,
                {"started", "completed"},
                path .. ".state",
                true
            )
        end,
        evaluate = function(condition)
            return progress[condition.state] == true
        end,
    })

    host:registerWorldInitializer(
        "game_flow",
        5,
        function(world)
            stateFor(world)
            world.events:on("actor.killed", function(payload)
                local target = payload.target_id and
                    world:get(payload.target_id) or nil
                if target and target.tag_set.player then
                    setMode(world, "gameover")
                    world.events:emit("game.over", {
                        entity_id = target.id,
                    })
                end
            end)
            return true
        end
    )
    for _, channel in ipairs({"move", "act", "interact"}) do
        host:registerGate(
            channel,
            "game_flow.modal",
            function(entity, world)
                if entity.tag_set.player and
                   stateFor(world).mode ~= "playing" then
                    return false, "game_flow"
                end
                return true
            end
        )
    end
    host:registerTimeFilter(
        "game_flow.modal",
        1,
        function(world, dt)
            if stateFor(world).mode ~= "playing" then return 0 end
            return dt
        end
    )
    host:registerAppController(
        "game_flow.input",
        10,
        function(world, dt)
            local state = stateFor(world)
            if state.notice_remaining > 0 then
                state.notice_remaining =
                    math.max(0, state.notice_remaining - dt)
                if state.notice_remaining == 0 then
                    state.notice = nil
                end
            end
            if state.mode == "playing" then
                if input:consumePressed("pause") then
                    setMode(world, "paused")
                    return true
                end
                return false
            end

            local options = optionsFor(world)
            if input:consumePressed("menu_up") then
                state.selected = state.selected - 1
                if state.selected < 1 then
                    state.selected = #options
                end
            elseif input:consumePressed("menu_down") then
                state.selected = state.selected + 1
                if state.selected > #options then
                    state.selected = 1
                end
            end
            local menu_left = input:hasAction("menu_left") and
                input:consumePressed("menu_left") or false
            local menu_right = input:hasAction("menu_right") and
                input:consumePressed("menu_right") or false
            local menu_cancel = input:consumePressed("menu_cancel")
            if menu_cancel and
               state.panel == "accessibility" then
                state.panel = nil
                state.selected = 1
            elseif menu_cancel and
               state.mode == "paused" then
                setMode(world, "playing")
            elseif state.panel == "accessibility" and
               menu_left ~= menu_right then
                local option = options[state.selected]
                if option then
                    activate(world, option, menu_left and -1 or 1)
                end
            elseif input:consumePressed("menu_confirm") then
                local option = options[state.selected]
                if option then activate(world, option) end
            end
            return true
        end
    )

    host:registerWorldInspector("game_flow", function(world)
        local state = stateFor(world)
        local option_ids = {}
        for _, option in ipairs(optionsFor(world)) do
            option_ids[#option_ids + 1] = option.id
        end
        return {
            game_flow = {
                mode = state.mode,
                selected = state.selected,
                options = option_ids,
                has_save = hasSave(),
                started = progress.started,
                completed = progress.completed,
                notice = state.notice,
                panel = state.panel,
                accessibility =
                    world:service("accessibility"):inspect(),
            },
        }
    end)

    local draw_system = {
        id = "game_flow.draw",
        draw_order = 10000,
        draw_space = "screen",
    }
    function draw_system:draw(world)
        local state = stateFor(world)
        if state.mode == "playing" then return end
        local view = world:view()
        local palette = {
            title = {0.018, 0.035, 0.055, 1},
            paused = {0.018, 0.025, 0.04, 0.9},
            gameover = {0.12, 0.018, 0.025, 1},
            ending = {0.07, 0.055, 0.018, 1},
        }
        local color = palette[state.mode] or palette.title
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", 0, 0, view.width, view.height)

        local screen
        local heading
        local message
        if state.panel == "accessibility" then
            local locale = world:service("locale")
            heading = locale and locale:text(
                "accessibility.heading",
                "Accessibility"
            ) or "Accessibility"
            message = locale and locale:text(
                "accessibility.message",
                "Adjust visual feedback and message duration."
            ) or "Adjust visual feedback and message duration."
        elseif state.mode == "title" then
            screen = config.title
            heading = screenText(
                world,
                screen,
                "heading",
                host.manifest.title
            )
            message = screenText(
                world,
                screen,
                "message",
                "A complete Recreate sample game"
            )
        elseif state.mode == "paused" then
            heading = screenText(
                world,
                nil,
                "heading",
                "Paused"
            )
            local locale = world:service("locale")
            if locale then
                heading = locale:text("flow.pause.heading", heading)
            end
            message = ""
        elseif state.mode == "gameover" then
            screen = config.game_over
            heading = screenText(
                world,
                screen,
                "heading",
                "Game Over"
            )
            message = screenText(
                world,
                screen,
                "message",
                "The forest remains in danger."
            )
        else
            screen = config.ending
            heading = screenText(
                world,
                screen,
                "heading",
                "The End"
            )
            message = screenText(
                world,
                screen,
                "message",
                "The quiet forest is safe again."
            )
        end

        local previous_font = love.graphics.getFont()
        local title_font = previous_font
        local font_config = host.manifest.font or {}
        if font_config.asset then
            title_font = host.assets:font(font_config.asset, 34)
        end
        love.graphics.setFont(title_font)
        love.graphics.setColor(1, 0.9, 0.58, 1)
        love.graphics.printf(
            heading,
            64,
            82,
            view.width - 128,
            "center"
        )
        love.graphics.setFont(previous_font)
        love.graphics.setColor(0.84, 0.88, 0.94, 1)
        love.graphics.printf(
            message,
            96,
            142,
            view.width - 192,
            "center"
        )

        local options = optionsFor(world)
        local y = 220
        for index, option in ipairs(options) do
            local selected = index == state.selected
            if selected then
                love.graphics.setColor(0.2, 0.62, 0.88, 0.35)
                love.graphics.rectangle(
                    "fill",
                    view.width / 2 - 150,
                    y - 7,
                    300,
                    34,
                    7,
                    7
                )
            end
            love.graphics.setColor(
                selected and 1 or 0.72,
                selected and 0.9 or 0.76,
                selected and 0.52 or 0.82,
                1
            )
            love.graphics.printf(
                (selected and ">  " or "   ") .. option.label,
                view.width / 2 - 150,
                y,
                300,
                "center"
            )
            y = y + 46
        end
        if state.notice then
            love.graphics.setColor(
                state.notice_success and 0.4 or 1,
                state.notice_success and 1 or 0.4,
                0.5,
                1
            )
            love.graphics.printf(
                state.notice,
                80,
                view.height - 62,
                view.width - 160,
                "center"
            )
        end
        love.graphics.setColor(0.65, 0.7, 0.78, 1)
        local locale = world:service("locale")
        love.graphics.printf(
            locale and locale:text(
                "flow.controls",
                "Up/Down  Select    Enter  Confirm    Esc  Back"
            ) or "Up/Down  Select    Enter  Confirm    Esc  Back",
            40,
            view.height - 34,
            view.width - 80,
            "center"
        )
        love.graphics.setColor(1, 1, 1, 1)
    end
    host:registerSystem(draw_system)
end

return feature

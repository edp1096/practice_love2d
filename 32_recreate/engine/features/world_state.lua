local Schema = require "engine.runtime.session_schema"
local util = require "engine.core.util"

local feature = {
    id = "world_state",
    requires = {
        "engine.features.session",
        "engine.features.geometry",
    },
}

local MINUTES_PER_DAY = 24 * 60

local function parseClock(value)
    if type(value) ~= "string" then return nil end
    local hour, minute = value:match("^(%d%d?):(%d%d)$")
    hour = tonumber(hour)
    minute = tonumber(minute)
    if not hour or not minute or hour > 23 or minute > 59 then
        return nil
    end
    return hour * 60 + minute
end

local function formatClock(minute)
    minute = math.floor(minute % MINUTES_PER_DAY)
    return string.format(
        "%02d:%02d",
        math.floor(minute / 60),
        minute % 60
    )
end

local function validateClock(value, validator, path, required)
    value = validator:string(value, path, required)
    if value and not parseClock(value) then
        validator:error(path, "must use 24-hour HH:MM time")
    end
end

local function validateColor(color, validator, path)
    color = validator:array(color, path, false)
    if not color then return end
    if #color ~= 4 then
        validator:error(path, "must contain RGBA values")
    end
    for index, component in ipairs(color) do
        component = validator:number(
            component,
            string.format("%s[%d]", path, index),
            true
        )
        if component and (component < 0 or component > 1) then
            validator:error(
                string.format("%s[%d]", path, index),
                "must be between 0 and 1"
            )
        end
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

local function validateRegions(regions, validator, host, geometry)
    regions = validator:array(regions, "world_state.regions", false)
    local seen = {}
    for index, region in ipairs(regions or {}) do
        local path = string.format("world_state.regions[%d]", index)
        if validator:table(region, path, true) then
            validator:keys(
                region,
                {
                    "id", "shape", "actor_tag", "condition",
                    "on_enter", "on_exit",
                },
                path
            )
            local id = validator:string(region.id, path .. ".id", true)
            if id and seen[id] then
                validator:error(path .. ".id", "duplicates another region id")
            elseif id then
                seen[id] = true
            end
            geometry:validateShape(
                region.shape,
                validator,
                path .. ".shape"
            )
            validator:string(
                region.actor_tag,
                path .. ".actor_tag",
                false
            )
            if region.condition then
                host.rules:validateCondition(
                    region.condition,
                    validator,
                    path .. ".condition"
                )
            end
            validateActions(
                region.on_enter,
                validator,
                host,
                path .. ".on_enter"
            )
            validateActions(
                region.on_exit,
                validator,
                host,
                path .. ".on_exit"
            )
        end
    end
end

local function validatePages(pages, validator, host)
    pages = validator:array(pages, "world_state.pages", false)
    local seen = {}
    for index, page in ipairs(pages or {}) do
        local path = string.format("world_state.pages[%d]", index)
        if validator:table(page, path, true) then
            validator:keys(
                page,
                {
                    "id", "condition", "tint", "layers",
                    "on_enter", "on_exit",
                },
                path
            )
            local id = validator:string(page.id, path .. ".id", true)
            if id and seen[id] then
                validator:error(path .. ".id", "duplicates another page id")
            elseif id then
                seen[id] = true
            end
            if page.condition then
                host.rules:validateCondition(
                    page.condition,
                    validator,
                    path .. ".condition"
                )
            end
            validateColor(page.tint, validator, path .. ".tint")
            local layers = validator:array(
                page.layers,
                path .. ".layers",
                false
            )
            local seen_layers = {}
            for layer_index, layer in ipairs(layers or {}) do
                local layer_path = string.format(
                    "%s.layers[%d]",
                    path,
                    layer_index
                )
                if validator:table(layer, layer_path, true) then
                    validator:keys(layer, {"id", "visible"}, layer_path)
                    local layer_id = validator:string(
                        layer.id,
                        layer_path .. ".id",
                        true
                    )
                    if layer_id and seen_layers[layer_id] then
                        validator:error(
                            layer_path .. ".id",
                            "duplicates another layer override"
                        )
                    elseif layer_id then
                        seen_layers[layer_id] = true
                    end
                    validator:boolean(
                        layer.visible,
                        layer_path .. ".visible",
                        true
                    )
                end
            end
            validateActions(
                page.on_enter,
                validator,
                host,
                path .. ".on_enter"
            )
            validateActions(
                page.on_exit,
                validator,
                host,
                path .. ".on_exit"
            )
        end
    end
end

local function drawShape(shape)
    if shape.type == "rectangle" then
        love.graphics.rectangle(
            "line",
            shape.x - shape.width / 2,
            shape.y - shape.height / 2,
            shape.width,
            shape.height
        )
    elseif shape.type == "polygon" then
        local coordinates = {}
        for _, point in ipairs(shape.points or {}) do
            coordinates[#coordinates + 1] = point.x
            coordinates[#coordinates + 1] = point.y
        end
        if #coordinates >= 6 then
            love.graphics.polygon("line", coordinates)
        end
    end
end

function feature:register(host)
    local manifest = host.manifest.world or {}
    local start_minute = parseClock(manifest.start_time or "08:00")
    assert(
        start_minute,
        "game manifest world.start_time must use 24-hour HH:MM time"
    )
    local seconds_per_day = manifest.seconds_per_day or 0
    assert(
        type(seconds_per_day) == "number" and seconds_per_day >= 0,
        "game manifest world.seconds_per_day must be non-negative"
    )

    local session = host.services.session
    session:registerSection("world.state", {
        version = 1,
        defaults = {
            day = 1,
            minute = start_minute,
        },
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "world.state",
                {"day", "minute"},
                {"day", "minute"}
            )
            if not valid then return nil, value_error end
            valid, value_error = Schema.positiveInteger(
                value.day,
                "world.state.day"
            )
            if not valid then return nil, value_error end
            if type(value.minute) ~= "number" or
               value.minute < 0 or
               value.minute >= MINUTES_PER_DAY then
                return nil,
                    "world.state.minute must be between 0 and 1439.999"
            end
            return true
        end,
    })

    local world_state = {}

    local function persistent()
        return session:peek("world.state")
    end

    local function stateFor(world)
        return world.feature_state.world_state
    end

    local function timeBetween(start_time, finish_time)
        local minute = persistent().minute
        local start_minute_value = parseClock(start_time)
        local finish_minute_value = parseClock(finish_time)
        if start_minute_value == finish_minute_value then return true end
        if start_minute_value < finish_minute_value then
            return minute >= start_minute_value and
                minute < finish_minute_value
        end
        return minute >= start_minute_value or
            minute < finish_minute_value
    end

    local function applyLayerOverrides(world, page)
        local tilemap = world.feature_state.tilemap
        local state = stateFor(world)
        if not tilemap or not state then return end
        for _, layer in ipairs(tilemap.layers or {}) do
            local base = state.layer_visibility[layer.id]
            if base ~= nil then layer.visible = base end
        end
        for _, override in ipairs(page and page.layers or {}) do
            for _, layer in ipairs(tilemap.layers or {}) do
                if layer.id == override.id then
                    layer.visible = override.visible
                    break
                end
            end
        end
    end

    local function executeActions(world, actions, context)
        if not actions or #actions == 0 then return true end
        local result, action_error =
            world:executeActions(actions, context)
        return result ~= nil, action_error
    end

    local function selectPage(world)
        local state = stateFor(world)
        local selected
        for _, page in ipairs(state.pages) do
            if host.rules:evaluate(
                page.condition or {type = "always"},
                {world = world, events = world.events}
            ) then
                selected = page
            end
        end
        return selected
    end

    local function refreshPage(world, initial)
        local state = stateFor(world)
        if not state then return true end
        local selected = selectPage(world)
        local selected_id = selected and selected.id or nil
        if selected_id == state.active_page then return true end

        local previous = state.page_by_id[state.active_page]
        local context = {
            world = world,
            events = world.events,
            previous_page = state.active_page,
            world_page = selected_id,
        }
        if previous and not initial then
            local exited, exit_error = executeActions(
                world,
                previous.on_exit,
                context
            )
            if not exited then return nil, exit_error end
        end
        state.active_page = selected_id
        applyLayerOverrides(world, selected)
        if selected and not initial then
            local entered, enter_error = executeActions(
                world,
                selected.on_enter,
                context
            )
            if not entered then return nil, enter_error end
        end
        world.events:emit("world.page.changed", {
            previous = previous and previous.id or nil,
            current = selected_id,
        })
        return true
    end

    local function setMinute(world, minute, day)
        local state = persistent()
        local previous_minute = state.minute
        local previous_day = state.day
        local total = minute
        local day_offset = math.floor(total / MINUTES_PER_DAY)
        total = total % MINUTES_PER_DAY
        state.minute = total
        state.day = math.max(1, (day or state.day) + day_offset)
        local refreshed, refresh_error = refreshPage(world, false)
        if not refreshed then return nil, refresh_error end
        world.events:emit("world.time.changed", {
            previous_day = previous_day,
            previous_minute = previous_minute,
            day = state.day,
            minute = state.minute,
            clock = formatClock(state.minute),
        })
        return {
            applied = previous_day ~= state.day or
                previous_minute ~= state.minute,
            day = state.day,
            minute = state.minute,
            clock = formatClock(state.minute),
        }
    end

    function world_state:time()
        local state = persistent()
        return {
            day = state.day,
            minute = state.minute,
            clock = formatClock(state.minute),
        }
    end

    function world_state:setTime(world, clock, day)
        local minute = parseClock(clock)
        if not minute then return nil, "invalid world time " .. tostring(clock) end
        return setMinute(world, minute, day)
    end

    function world_state:advance(world, minutes)
        return setMinute(world, persistent().minute + minutes)
    end

    function world_state:regionActive(world, id)
        local state = stateFor(world)
        return state and state.active_regions[id] == true or false
    end

    host.rules:registerAction("set_world_time", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "time", "day"}, path)
            validateClock(action.time, validator, path .. ".time", true)
            local day = validator:number(
                action.day,
                path .. ".day",
                false
            )
            if day and (day < 1 or day % 1 ~= 0) then
                validator:error(path .. ".day", "must be a positive integer")
            end
        end,
        execute = function(action, context)
            return world_state:setTime(
                context.world,
                action.time,
                action.day
            )
        end,
    })
    host.rules:registerAction("advance_world_time", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "minutes"}, path)
            validator:positive(
                action.minutes,
                path .. ".minutes",
                true
            )
        end,
        execute = function(action, context)
            return world_state:advance(
                context.world,
                action.minutes
            )
        end,
    })
    host.rules:registerCondition("time_between", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "start", "finish"},
                path
            )
            validateClock(
                condition.start,
                validator,
                path .. ".start",
                true
            )
            validateClock(
                condition.finish,
                validator,
                path .. ".finish",
                true
            )
        end,
        evaluate = function(condition)
            return timeBetween(condition.start, condition.finish)
        end,
    })
    host.rules:registerCondition("region_active", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "id"}, path)
            validator:string(condition.id, path .. ".id", true)
        end,
        evaluate = function(condition, context)
            return context.world and
                world_state:regionActive(context.world, condition.id)
        end,
    })

    host:registerStageSection("world_state", {
        priority = 15,
        validate = function(config, validator)
            if config == nil then return end
            if not validator:table(
                config,
                "world_state",
                true
            ) then
                return
            end
            validator:keys(
                config,
                {"regions", "pages"},
                "world_state"
            )
            validateRegions(
                config.regions,
                validator,
                host,
                host.services.geometry
            )
            validatePages(config.pages, validator, host)
        end,
        load = function(world, config)
            config = util.deepCopy(config or {})
            local state = {
                regions = config.regions or {},
                pages = config.pages or {},
                region_by_id = {},
                page_by_id = {},
                active_regions = {},
                active_page = nil,
                layer_visibility = {},
            }
            for _, region in ipairs(state.regions) do
                state.region_by_id[region.id] = region
            end
            for _, page in ipairs(state.pages) do
                state.page_by_id[page.id] = page
            end
            local tilemap = world.feature_state.tilemap
            for _, layer in ipairs(tilemap and tilemap.layers or {}) do
                state.layer_visibility[layer.id] =
                    layer.visible ~= false
            end
            world.feature_state.world_state = state
            return true
        end,
    })

    host:registerWorldInitializer("world_state", 80, function(world)
        local refreshed, refresh_error = refreshPage(world, true)
        if not refreshed then return nil, refresh_error end
        return true
    end)

    local update_system = {
        id = "world_state.update",
        phase = "resolution",
        order = 900,
    }

    function update_system:update(world, dt)
        if seconds_per_day > 0 then
            local advanced, advance_error = world_state:advance(
                world,
                dt * MINUTES_PER_DAY / seconds_per_day
            )
            if not advanced then
                world.events:emit("world.time.failed", {
                    error = tostring(advance_error),
                })
            end
        else
            local refreshed, refresh_error = refreshPage(world, false)
            if not refreshed then
                world.events:emit("world.page.failed", {
                    error = tostring(refresh_error),
                })
            end
        end

        local state = stateFor(world)
        for _, region in ipairs(state.regions) do
            local actor_tag = region.actor_tag or "player"
            local inside = false
            local condition_matches = host.rules:evaluate(
                region.condition or {type = "always"},
                {world = world, events = world.events}
            )
            if condition_matches then
                for _, entity in ipairs(world:findByTag(actor_tag)) do
                    if host.services.geometry:containsEntity(
                        region.shape,
                        entity
                    ) then
                        inside = true
                        break
                    end
                end
            end
            local was_inside = state.active_regions[region.id] == true
            if inside ~= was_inside then
                state.active_regions[region.id] = inside or nil
                local event_name = inside and
                    "world.region.entered" or
                    "world.region.exited"
                local context = {
                    world = world,
                    events = world.events,
                    region_id = region.id,
                }
                local actions = inside and
                    region.on_enter or region.on_exit
                local executed, action_error =
                    executeActions(world, actions, context)
                world.events:emit(event_name, {
                    region_id = region.id,
                    actor_tag = actor_tag,
                    actions_applied = executed,
                    error = action_error,
                })
            end
        end
    end

    local overlay_system = {
        id = "world_state.overlay",
        draw_order = -100,
        draw_space = "screen",
    }

    function overlay_system:draw(world)
        local state = stateFor(world)
        local page = state and state.page_by_id[state.active_page]
        local tint = page and page.tint
        if not tint or tint[4] <= 0 then return end
        local view = world:view()
        love.graphics.setColor(tint)
        love.graphics.rectangle(
            "fill",
            0,
            0,
            view.width,
            view.height
        )
        love.graphics.setColor(1, 1, 1, 1)
    end

    host:registerService("world_state", world_state)
    host:registerSystem(update_system)
    host:registerSystem(overlay_system)
    host:registerWorldInspector("world_state", function(world)
        local state = stateFor(world)
        local time = world_state:time()
        local active_regions = util.sortedKeys(
            state and state.active_regions or {}
        )
        return {
            world_state = {
                day = time.day,
                minute = time.minute,
                clock = time.clock,
                active_page = state and state.active_page or nil,
                active_regions = active_regions,
                region_count = state and #state.regions or 0,
                page_count = state and #state.pages or 0,
                seconds_per_day = seconds_per_day,
            },
        }
    end)
    host:registerDebugDrawer("world_state", function(world, options)
        if not options.entities then return end
        local state = stateFor(world)
        love.graphics.setColor(0.72, 0.42, 1, 0.9)
        for _, region in ipairs(state and state.regions or {}) do
            drawShape(region.shape)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end)
end

return feature

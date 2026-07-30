local util = require "engine.core.util"
local EventPages = require "engine.core.event_pages"

local feature = {
    id = "navigation",
    requires = {
        "engine.features.world",
        "engine.features.geometry",
    },
}

local function validateUniqueItems(
    items,
    validator,
    path,
    validate_item
)
    items = validator:array(items, path, false)
    local seen = {}
    for index, item in ipairs(items or {}) do
        local item_path = string.format("%s[%d]", path, index)
        if validator:table(item, item_path, true) then
            local id = validator:string(
                item.id,
                item_path .. ".id",
                true
            )
            if id and seen[id] then
                validator:error(item_path .. ".id", "duplicates another id")
            elseif id then
                seen[id] = true
            end
            validate_item(item, validator, item_path)
        end
    end
end

local function validateSpawnPoints(points, validator, path, stage)
    validateUniqueItems(points, validator, path, function(
        point,
        current_validator,
        item_path
    )
        current_validator:keys(point, {"id", "x", "y"}, item_path)
        local x = current_validator:number(
            point.x,
            item_path .. ".x",
            true
        )
        local y = current_validator:number(
            point.y,
            item_path .. ".y",
            true
        )
        if x and (x < 0 or x > stage.width) then
            current_validator:error(
                item_path .. ".x",
                "must be inside stage bounds"
            )
        end
        if y and (y < 0 or y > stage.height) then
            current_validator:error(
                item_path .. ".y",
                "must be inside stage bounds"
            )
        end
    end)
end

local function findSpawnPoint(stage, spawn_id)
    for _, point in ipairs(stage.spawn_points or {}) do
        if point.id == spawn_id then return point end
    end
    return nil
end

local function validateCooldown(value, validator, path)
    value = validator:number(value, path, false)
    if value and value < 0 then
        validator:error(path, "must not be negative")
    end
end

local function validatePortals(host, portals, validator, path)
    validateUniqueItems(portals, validator, path, function(
        portal,
        current_validator,
        item_path
    )
        current_validator:keys(
            portal,
            {
                "id", "shape", "actor_tag",
                "target_stage", "target_spawn", "cooldown",
            },
            item_path
        )
        host.services.geometry:validateShape(
            portal.shape,
            current_validator,
            item_path .. ".shape"
        )
        current_validator:string(
            portal.actor_tag,
            item_path .. ".actor_tag",
            false
        )
        local target_stage = current_validator:reference(
            portal.target_stage,
            "stage",
            item_path .. ".target_stage"
        )
        local target_spawn = current_validator:string(
            portal.target_spawn,
            item_path .. ".target_spawn",
            true
        )
        if target_stage and target_spawn and
           not findSpawnPoint(target_stage, target_spawn) then
            current_validator:error(
                item_path .. ".target_spawn",
                string.format(
                    "stage '%s' has no spawn point '%s'",
                    target_stage.id,
                    target_spawn
                )
            )
        end
        validateCooldown(
            portal.cooldown,
            current_validator,
            item_path .. ".cooldown"
        )
    end)
end

local function validateTriggers(host, triggers, validator, path)
    validateUniqueItems(triggers, validator, path, function(
        trigger,
        current_validator,
        item_path
    )
        current_validator:keys(
            trigger,
            {
                "id", "shape", "actor_tag", "once", "cooldown",
                "condition", "actions", "pages",
            },
            item_path
        )
        host.services.geometry:validateShape(
            trigger.shape,
            current_validator,
            item_path .. ".shape"
        )
        current_validator:string(
            trigger.actor_tag,
            item_path .. ".actor_tag",
            false
        )
        current_validator:boolean(
            trigger.once,
            item_path .. ".once",
            false
        )
        validateCooldown(
            trigger.cooldown,
            current_validator,
            item_path .. ".cooldown"
        )
        if trigger.condition then
            host.rules:validateCondition(
                trigger.condition,
                current_validator,
                item_path .. ".condition"
            )
        end
        local function validateActions(actions, path, required)
            actions = current_validator:array(
                actions,
                path,
                required
            )
            if actions and #actions == 0 then
                current_validator:error(
                    path,
                    "must contain at least one action"
                )
            end
            for index, action in ipairs(actions or {}) do
                host.rules:validateAction(
                    action,
                    current_validator,
                    string.format("%s[%d]", path, index)
                )
            end
        end
        local pages = EventPages.validate(
            host,
            trigger.pages,
            current_validator,
            item_path .. ".pages",
            function(page, page_validator, page_path)
                page_validator:keys(
                    page,
                    {
                        "id", "condition", "once",
                        "cooldown", "actions",
                    },
                    page_path
                )
                page_validator:boolean(
                    page.once,
                    page_path .. ".once",
                    false
                )
                validateCooldown(
                    page.cooldown,
                    page_validator,
                    page_path .. ".cooldown"
                )
                validateActions(
                    page.actions,
                    page_path .. ".actions",
                    true
                )
            end
        )
        validateActions(
            trigger.actions,
            item_path .. ".actions",
            not pages
        )
    end)
end

local function createState(world)
    local state = world.feature_state.navigation
    if not state then
        state = {
            spawn_points = {},
            triggers = {},
            portals = {},
            inside = {},
            cooldowns = {},
            fired = {},
            transition_requested = false,
        }
        world.feature_state.navigation = state
    end
    return state
end

local function updateCooldowns(state, dt)
    for key, remaining in pairs(state.cooldowns) do
        remaining = math.max(0, remaining - dt)
        if remaining == 0 then
            state.cooldowns[key] = nil
        else
            state.cooldowns[key] = remaining
        end
    end
end

local function eachEntry(world, entries, handler)
    local geometry = world:service("geometry")
    local state = createState(world)
    for _, entry in ipairs(entries) do
        local actors = world:findByTag(entry.actor_tag or "player")
        for _, actor in ipairs(actors) do
            local key = entry.id .. "\0" .. actor.id
            local inside = geometry:containsEntity(entry.shape, actor)
            local entered = inside and not state.inside[key]
            state.inside[key] = inside or nil
            if entered then handler(entry, actor, key, state) end
        end
    end
end

local navigation_system = {
    id = "navigation.resolve",
    phase = "resolution",
    order = 80,
}

function navigation_system:update(world, dt)
    local state = createState(world)
    updateCooldowns(state, dt)

    eachEntry(world, state.triggers, function(trigger, actor, key)
        if state.fired[trigger.id] or state.cooldowns[key] then return end
        local context = {
            target = actor,
            source = nil,
            trigger = trigger,
            world = world,
            events = world.events,
        }
        if trigger.condition and
           not world.host.rules:evaluate(trigger.condition, context) then
            return
        end
        local page
        if #(trigger.pages or {}) > 0 then
            page = EventPages.select(
                world.host.rules,
                trigger.pages,
                context
            )
            if not page then return end
        end
        local fired_id = page and
            (trigger.id .. "::" .. page.id) or trigger.id
        if state.fired[fired_id] then return end
        local actions = page and page.actions or trigger.actions
        local once = page and page.once
        if once == nil then once = trigger.once end
        local cooldown = page and page.cooldown
        if cooldown == nil then cooldown = trigger.cooldown or 0 end

        world.events:emit("trigger.entered", {
            trigger_id = trigger.id,
            page_id = page and page.id or nil,
            entity_id = actor.id,
        })
        local result, action_error, failure =
            world:executeActions(actions, context)
        if result then
            if once then state.fired[fired_id] = true end
            if cooldown > 0 then
                state.cooldowns[key] = cooldown
            end
        else
            world.events:emit("trigger.action_failed", {
                trigger_id = trigger.id,
                entity_id = actor.id,
                action_index = failure and failure.index or nil,
                action_type = failure and failure.action.type or nil,
                error = action_error,
            })
        end
    end)

    if state.transition_requested then return end
    eachEntry(world, state.portals, function(portal, actor, key)
        if state.transition_requested or state.cooldowns[key] then return end
        state.transition_requested = true
        world.events:emit("portal.entered", {
            portal_id = portal.id,
            entity_id = actor.id,
            target_stage = portal.target_stage,
            target_spawn = portal.target_spawn,
        })
        world:request({
            type = "stage_transition",
            portal_id = portal.id,
            entity_id = actor.id,
            target_stage = portal.target_stage,
            target_spawn = portal.target_spawn,
        })
    end)
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
    else
        local coordinates = {}
        for _, point in ipairs(shape.points) do
            coordinates[#coordinates + 1] = point.x
            coordinates[#coordinates + 1] = point.y
        end
        love.graphics.polygon("line", coordinates)
    end
end

function feature:register(host)
    host.rules:registerAction("emit", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "name", "data"}, path)
            validator:string(action.name, path .. ".name", true)
            validator:table(action.data, path .. ".data", false)
        end,
        execute = function(action, context)
            local payload = util.deepCopy(action.data or {})
            payload.entity_id =
                context.target and context.target.id or nil
            payload.trigger_id =
                context.trigger and context.trigger.id or nil
            context.events:emit(action.name, payload)
            return {applied = true}
        end,
    })

    host:registerStageSection("spawn_points", {
        priority = 20,
        validate = validateSpawnPoints,
        load = function(world, points)
            createState(world).spawn_points =
                util.deepCopy(points or {})
            return true
        end,
    })
    host:registerStageSection("triggers", {
        priority = 30,
        validate = function(value, validator, path)
            validateTriggers(host, value, validator, path)
        end,
        load = function(world, triggers)
            createState(world).triggers =
                util.deepCopy(triggers or {})
            return true
        end,
    })
    host:registerStageSection("portals", {
        priority = 40,
        validate = function(value, validator, path)
            validatePortals(host, value, validator, path)
        end,
        load = function(world, portals)
            createState(world).portals =
                util.deepCopy(portals or {})
            return true
        end,
    })
    host:registerWorldInspector("navigation", function(world)
        local state = createState(world)
        local active = 0
        for _ in pairs(state.inside) do active = active + 1 end
        local fired = {}
        for id in pairs(state.fired) do fired[#fired + 1] = id end
        table.sort(fired)
        local spawn_points = util.deepCopy(state.spawn_points)
        local triggers = {}
        for _, trigger in ipairs(state.triggers) do
            triggers[#triggers + 1] = {
                id = trigger.id,
                shape = util.deepCopy(trigger.shape),
                actor_tag = trigger.actor_tag,
                once = trigger.once == true,
                cooldown = trigger.cooldown or 0,
                page_count = #(trigger.pages or {}),
            }
        end
        local portals = {}
        for _, portal in ipairs(state.portals) do
            portals[#portals + 1] = {
                id = portal.id,
                shape = util.deepCopy(portal.shape),
                actor_tag = portal.actor_tag,
                target_stage = portal.target_stage,
                target_spawn = portal.target_spawn,
                cooldown = portal.cooldown or 0,
            }
        end
        table.sort(spawn_points, function(a, b) return a.id < b.id end)
        table.sort(triggers, function(a, b) return a.id < b.id end)
        table.sort(portals, function(a, b) return a.id < b.id end)
        return {
            navigation = {
                spawn_point_count = #state.spawn_points,
                trigger_count = #state.triggers,
                portal_count = #state.portals,
                spawn_points = spawn_points,
                triggers = triggers,
                portals = portals,
                active_overlaps = active,
                fired_triggers = fired,
                transition_requested = state.transition_requested,
            },
        }
    end)
    host:registerDebugDrawer("navigation", function(world, options)
        if not options.entities then return end
        local state = createState(world)
        love.graphics.setColor(0.25, 1, 0.45, 0.9)
        for _, trigger in ipairs(state.triggers) do
            drawShape(trigger.shape)
        end
        love.graphics.setColor(0.75, 0.35, 1, 0.95)
        for _, portal in ipairs(state.portals) do
            drawShape(portal.shape)
        end
        love.graphics.setColor(1, 0.9, 0.2, 0.95)
        for _, point in ipairs(state.spawn_points) do
            love.graphics.line(
                point.x - 7,
                point.y,
                point.x + 7,
                point.y
            )
            love.graphics.line(
                point.x,
                point.y - 7,
                point.x,
                point.y + 7
            )
        end
    end)
    host:registerSystem(navigation_system)
end

return feature

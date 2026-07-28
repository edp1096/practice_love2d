local Events = require "engine.core.events"
local util = require "engine.core.util"

local World = {}
World.__index = World

local phase_order = {
    input = 10,
    intent = 20,
    movement = 30,
    combat = 40,
    resolution = 50,
    presentation = 60,
}

local function sortSystems(systems)
    local result = {}
    for index, system in ipairs(systems) do result[index] = system end
    table.sort(result, function(left, right)
        local left_phase = phase_order[left.phase or "resolution"] or 100
        local right_phase = phase_order[right.phase or "resolution"] or 100
        if left_phase ~= right_phase then return left_phase < right_phase end
        local left_order = left.order or 0
        local right_order = right.order or 0
        if left_order ~= right_order then return left_order < right_order end
        return left.id < right.id
    end)
    return result
end

function World.new(host, stage)
    return setmetatable({
        host = host,
        stage = stage,
        events = Events.new(200),
        entities = {},
        entity_order = {},
        pending_removal = {},
        requests = {},
        feature_state = {},
        systems = sortSystems(host.systems),
        time = 0,
        ticks = 0,
        spawn_sequence = 0,
    }, World)
end

local function tagsFrom(actor_tags, instance_tags)
    local tags = {}
    local tag_set = {}
    for _, source in ipairs({actor_tags or {}, instance_tags or {}}) do
        for _, tag in ipairs(source) do
            if not tag_set[tag] then
                tag_set[tag] = true
                tags[#tags + 1] = tag
            end
        end
    end
    table.sort(tags)
    return tags, tag_set
end

function World:spawn(actor_id, instance)
    instance = instance or {}
    local actor = self.host.catalog:get(actor_id)
    if not actor or actor.kind ~= "actor" then
        return nil, "missing actor '" .. tostring(actor_id) .. "'"
    end

    self.spawn_sequence = self.spawn_sequence + 1
    local entity_id =
        instance.id or string.format("%s.%d", actor_id, self.spawn_sequence)
    if self.entities[entity_id] then
        return nil, "duplicate entity id '" .. entity_id .. "'"
    end

    local tags, tag_set = tagsFrom(actor.tags, instance.tags)
    local component_configs =
        util.merge(actor.components, instance.components)
    if instance.position then
        component_configs.transform =
            util.merge(component_configs.transform, instance.position)
    end

    local entity = {
        id = entity_id,
        actor_id = actor_id,
        name = instance.name or actor.name or entity_id,
        tags = tags,
        tag_set = tag_set,
        components = {},
        commands = {},
        dead = false,
    }

    for _, name in ipairs(util.sortedKeys(component_configs)) do
        local definition = self.host.components[name]
        if not definition then
            return nil, "actor '" .. actor_id ..
                "' uses unknown component '" .. name .. "'"
        end
        local config = util.deepCopy(component_configs[name])
        entity.components[name] = definition.create and
            definition.create(config, entity, self) or config
    end

    self.entities[entity_id] = entity
    self.entity_order[#self.entity_order + 1] = entity_id
    self.events:emit("entity.spawned", {
        entity_id = entity_id,
        actor_id = actor_id,
    })
    return entity
end

function World:load()
    for _, spawn in ipairs(self.stage.spawns or {}) do
        local entity, spawn_error = self:spawn(spawn.actor, spawn)
        if not entity then return nil, spawn_error end
    end
    for _, section in ipairs(self.host.stage_section_order) do
        local definition = self.host.stage_sections[section.name]
        if definition.load then
            local loaded, load_error = definition.load(
                self,
                self.stage[section.name],
                self.stage
            )
            if not loaded then
                return nil, load_error or
                    ("could not load stage section '" .. section.name .. "'")
            end
        end
    end
    for _, initializer in ipairs(self.host.world_initializers) do
        local initialized, initialize_error =
            initializer.handler(self)
        if initialized == nil or initialized == false then
            return nil, initialize_error or
                ("could not initialize world feature '" ..
                    initializer.name .. "'")
        end
    end
    self.events:emit("stage.loaded", {stage_id = self.stage.id})
    return true
end

function World:get(entity_id)
    return self.entities[entity_id]
end

function World:has(entity, component_name)
    return entity and entity.components[component_name] ~= nil
end

function World:query(...)
    local required = {...}
    local result = {}
    for _, entity_id in ipairs(self.entity_order) do
        local entity = self.entities[entity_id]
        if entity then
            local matches = true
            for _, component_name in ipairs(required) do
                if not entity.components[component_name] then
                    matches = false
                    break
                end
            end
            if matches then result[#result + 1] = entity end
        end
    end
    return result
end

function World:findByTag(tag)
    local result = {}
    for _, entity_id in ipairs(self.entity_order) do
        local entity = self.entities[entity_id]
        if entity and entity.tag_set[tag] then
            result[#result + 1] = entity
        end
    end
    return result
end

function World:remove(entity_or_id, reason)
    local entity_id = type(entity_or_id) == "table" and
        entity_or_id.id or entity_or_id
    if self.entities[entity_id] then
        self.pending_removal[entity_id] = reason or "removed"
    end
end

function World:_flushRemovals()
    for entity_id, reason in pairs(self.pending_removal) do
        local entity = self.entities[entity_id]
        if entity then
            self.entities[entity_id] = nil
            self.events:emit("entity.removed", {
                entity_id = entity_id,
                actor_id = entity.actor_id,
                reason = reason,
            })
        end
    end
    self.pending_removal = {}
end

function World:execute(action, context)
    context = context or {}
    context.world = self
    context.events = self.events
    return self.host.rules:execute(action, context)
end

function World:service(name)
    return self.host.services[name]
end

function World:request(request)
    assert(type(request) == "table", "world request must be a table")
    assert(type(request.type) == "string", "world request type is required")
    self.requests[#self.requests + 1] = request
end

function World:drainRequests()
    local requests = self.requests
    self.requests = {}
    return requests
end

function World:view()
    local camera = self:service("camera")
    if camera and camera.view then return camera:view(self) end
    return {
        x = 0,
        y = 0,
        width = self.stage.width,
        height = self.stage.height,
    }
end

function World:allows(entity, channel)
    for _, gate in ipairs(self.host.gates[channel] or {}) do
        local allowed, reason = gate.checker(entity, self)
        if allowed == false then
            return false, reason or gate.name
        end
    end
    return true
end

function World:update(dt)
    local raw_dt = dt
    for _, filter in ipairs(self.host.time_filters) do
        dt = filter.handler(self, dt, raw_dt)
        assert(
            type(dt) == "number" and dt >= 0,
            "time filter must return a non-negative number: " .. filter.name
        )
    end

    self.ticks = self.ticks + 1
    if dt == 0 then return false end
    self.time = self.time + dt
    for _, system in ipairs(self.systems) do
        if system.update then system:update(self, dt) end
    end
    self:_flushRemovals()
    return true
end

function World:draw(space)
    space = space or "world"
    local systems = {}
    for _, system in ipairs(self.systems) do
        if system.draw and (system.draw_space or "world") == space then
            systems[#systems + 1] = system
        end
    end
    table.sort(systems, function(left, right)
        local left_order = left.draw_order or 0
        local right_order = right.draw_order or 0
        if left_order ~= right_order then return left_order < right_order end
        return left.id < right.id
    end)
    for _, system in ipairs(systems) do system:draw(self) end
end

function World:drawDebug(options)
    for _, drawer in ipairs(self.host.debug_drawers) do
        drawer.handler(self, options or {})
    end
end

function World:snapshot()
    local entities = {}
    for _, entity_id in ipairs(self.entity_order) do
            local entity = self.entities[entity_id]
        if entity then
            local transform = entity.components.transform
            local snapshot = {
                id = entity.id,
                actor_id = entity.actor_id,
                name = entity.name,
                tags = util.deepCopy(entity.tags),
                dead = entity.dead,
                x = transform and transform.x or nil,
                y = transform and transform.y or nil,
                components = util.sortedKeys(entity.components),
            }
            for _, inspector in ipairs(self.host.entity_inspectors) do
                local fields = inspector.handler(entity, self) or {}
                for key, value in pairs(fields) do
                    assert(
                        snapshot[key] == nil,
                        "entity inspector field collision: " .. key
                    )
                    snapshot[key] = value
                end
            end
            entities[#entities + 1] = snapshot
        end
    end
    local snapshot = {
        available = true,
        stage = {
            id = self.stage.id,
            name = self.stage.name,
            width = self.stage.width,
            height = self.stage.height,
        },
        time = self.time,
        ticks = self.ticks,
        count = #entities,
        entities = entities,
        recent_events = self.events:recent(20),
        pending_requests = util.deepCopy(self.requests),
    }
    for _, inspector in ipairs(self.host.world_inspectors) do
        local fields = inspector.handler(self) or {}
        for key, value in pairs(fields) do
            assert(
                snapshot[key] == nil,
                "world inspector field collision: " .. key
            )
            snapshot[key] = value
        end
    end
    return snapshot
end

return World

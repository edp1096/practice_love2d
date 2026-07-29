local Catalog = require "engine.content.catalog"
local Input = require "engine.core.input"
local Rules = require "engine.core.rules"
local Assets = require "engine.runtime.assets"
local World = require "engine.runtime.world"

local Host = {}
Host.__index = Host

function Host.new(manifest, filesystem, session_store)
    session_store = session_store or {
        values = {},
        versions = {},
    }
    if type(session_store.values) ~= "table" or
       type(session_store.versions) ~= "table" then
        -- Compatibility for direct Host users that still pass the old raw
        -- namespace table. App and serialized saves always use a full store.
        session_store = {
            values = session_store,
            versions = {},
        }
    end
    local self = setmetatable({
        manifest = manifest,
        filesystem = filesystem,
        session_store = session_store,
        session = session_store.values,
        session_versions = session_store.versions,
        input = Input.new((manifest.input or {}).actions or {}),
        rules = Rules.new(),
        catalog = Catalog.new(filesystem),
        content_kinds = {},
        components = {},
        systems = {},
        gates = {},
        services = {},
        time_filters = {},
        entity_inspectors = {},
        world_inspectors = {},
        debug_drawers = {},
        stage_sections = {},
        stage_section_order = {},
        world_initializers = {},
        app_controllers = {},
        boot_validators = {},
        features = {},
        feature_modules = {},
        loading_features = {},
    }, Host)
    self.assets = Assets.new(self)
    return self
end

function Host:registerBootValidator(name, handler)
    assert(
        type(name) == "string" and name ~= "",
        "boot validator name is required"
    )
    assert(type(handler) == "function", "boot validator is required")
    for _, validator in ipairs(self.boot_validators) do
        assert(
            validator.name ~= name,
            "duplicate boot validator: " .. name
        )
    end
    self.boot_validators[#self.boot_validators + 1] = {
        name = name,
        handler = handler,
    }
    table.sort(self.boot_validators, function(left, right)
        return left.name < right.name
    end)
end

function Host:registerWorldInitializer(name, priority, handler)
    assert(
        type(name) == "string" and name ~= "",
        "world initializer name is required"
    )
    assert(
        type(handler) == "function",
        "world initializer handler is required"
    )
    for _, initializer in ipairs(self.world_initializers) do
        assert(
            initializer.name ~= name,
            "duplicate world initializer: " .. name
        )
    end
    self.world_initializers[#self.world_initializers + 1] = {
        name = name,
        priority = priority or 100,
        handler = handler,
    }
    table.sort(self.world_initializers, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end
        return left.name < right.name
    end)
end

function Host:registerAppController(name, priority, handler)
    assert(
        type(name) == "string" and name ~= "",
        "app controller name is required"
    )
    assert(type(handler) == "function", "app controller is required")
    for _, controller in ipairs(self.app_controllers) do
        assert(
            controller.name ~= name,
            "duplicate app controller: " .. name
        )
    end
    self.app_controllers[#self.app_controllers + 1] = {
        name = name,
        priority = priority or 100,
        handler = handler,
    }
    table.sort(self.app_controllers, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end
        return left.name < right.name
    end)
end

function Host:registerStageSection(name, definition)
    assert(type(name) == "string" and name ~= "", "stage section name is required")
    assert(type(definition) == "table", "stage section definition must be a table")
    assert(
        definition.validate == nil or type(definition.validate) == "function",
        "stage section validate must be a function"
    )
    assert(
        definition.load == nil or type(definition.load) == "function",
        "stage section load must be a function"
    )
    assert(not self.stage_sections[name], "duplicate stage section: " .. name)
    self.stage_sections[name] = definition
    self.stage_section_order[#self.stage_section_order + 1] = {
        name = name,
        priority = definition.priority or 100,
    }
    table.sort(self.stage_section_order, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end
        return left.name < right.name
    end)
end

function Host:registerService(name, service)
    assert(type(name) == "string" and name ~= "", "service name is required")
    assert(type(service) == "table", "service must be a table")
    assert(not self.services[name], "duplicate service: " .. name)
    self.services[name] = service
end

function Host:registerTimeFilter(name, priority, handler)
    assert(type(name) == "string" and name ~= "", "time filter name is required")
    assert(type(handler) == "function", "time filter handler is required")
    for _, filter in ipairs(self.time_filters) do
        assert(filter.name ~= name, "duplicate time filter: " .. name)
    end
    self.time_filters[#self.time_filters + 1] = {
        name = name,
        priority = priority or 100,
        handler = handler,
    }
    table.sort(self.time_filters, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end
        return left.name < right.name
    end)
end

local function registerInspector(registry, scope, name, handler)
    assert(type(name) == "string" and name ~= "", scope .. " inspector name is required")
    assert(type(handler) == "function", scope .. " inspector handler is required")
    for _, inspector in ipairs(registry) do
        assert(inspector.name ~= name, "duplicate " .. scope .. " inspector: " .. name)
    end
    registry[#registry + 1] = {name = name, handler = handler}
    table.sort(registry, function(left, right) return left.name < right.name end)
end

function Host:registerEntityInspector(name, handler)
    registerInspector(self.entity_inspectors, "entity", name, handler)
end

function Host:registerWorldInspector(name, handler)
    registerInspector(self.world_inspectors, "world", name, handler)
end

function Host:registerDebugDrawer(name, handler)
    registerInspector(self.debug_drawers, "debug drawer", name, handler)
end

function Host:registerGate(channel, name, checker)
    assert(type(channel) == "string" and channel ~= "", "gate channel is required")
    assert(type(name) == "string" and name ~= "", "gate name is required")
    assert(type(checker) == "function", "gate checker must be a function")
    local gates = self.gates[channel] or {}
    for _, gate in ipairs(gates) do
        assert(gate.name ~= name, "duplicate gate: " .. channel .. "." .. name)
    end
    gates[#gates + 1] = {name = name, checker = checker}
    table.sort(gates, function(left, right) return left.name < right.name end)
    self.gates[channel] = gates
end

function Host:registerContentKind(name, definition)
    assert(type(name) == "string" and name ~= "", "content kind is required")
    assert(type(definition) == "table", "content kind must be a table")
    assert(
        type(definition.validate) == "function",
        "content kind needs a validator"
    )
    assert(not self.content_kinds[name], "duplicate content kind: " .. name)
    self.content_kinds[name] = definition
end

function Host:registerComponent(name, definition)
    assert(type(name) == "string" and name ~= "", "component name is required")
    assert(type(definition) == "table", "component definition must be a table")
    if definition.requires ~= nil then
        assert(type(definition.requires) == "table", "component requires must be a table")
        for _, required in ipairs(definition.requires) do
            assert(
                type(required) == "string" and required ~= "",
                "required component name must be a string"
            )
        end
    end
    assert(
        definition.validateEntity == nil or
            type(definition.validateEntity) == "function",
        "component validateEntity must be a function"
    )
    assert(not self.components[name], "duplicate component: " .. name)
    self.components[name] = definition
end

function Host:registerSystem(system)
    assert(type(system) == "table", "system must be a table")
    assert(type(system.id) == "string", "system id is required")
    for _, existing in ipairs(self.systems) do
        assert(existing.id ~= system.id, "duplicate system: " .. system.id)
    end
    self.systems[#self.systems + 1] = system
end

function Host:loadFeature(module_name)
    if self.feature_modules[module_name] then return true end
    if self.loading_features[module_name] then
        return nil, "feature dependency cycle at " .. module_name
    end

    self.loading_features[module_name] = true
    local success, feature = pcall(require, module_name)
    if not success then
        self.loading_features[module_name] = nil
        return nil, "could not load feature " .. module_name .. ": " .. feature
    end
    if type(feature) ~= "table" or
       type(feature.id) ~= "string" or
       type(feature.register) ~= "function" then
        self.loading_features[module_name] = nil
        return nil, module_name .. " does not return a valid feature"
    end

    for _, dependency in ipairs(feature.requires or {}) do
        local loaded, load_error = self:loadFeature(dependency)
        if not loaded then
            self.loading_features[module_name] = nil
            return nil, load_error
        end
    end

    if self.features[feature.id] then
        self.loading_features[module_name] = nil
        return nil, "duplicate feature id '" .. feature.id .. "'"
    end

    local registered, register_error =
        pcall(feature.register, feature, self)
    if not registered then
        self.loading_features[module_name] = nil
        return nil, "could not register " .. module_name .. ": " .. register_error
    end

    self.features[feature.id] = feature
    self.feature_modules[module_name] = feature.id
    self.loading_features[module_name] = nil
    return true
end

function Host:boot()
    for _, module_name in ipairs(self.manifest.features or {}) do
        local loaded, load_error = self:loadFeature(module_name)
        if not loaded then return nil, load_error end
    end

    self.catalog:loadRoots(self.manifest.content_roots or {"game/content"})
    local valid, errors = self.catalog:validate(self)
    if not valid then
        return nil, table.concat(errors, "\n")
    end
    for _, validator in ipairs(self.boot_validators) do
        local validated, validation_error = validator.handler()
        if validated == nil or validated == false then
            return nil, validation_error or
                ("boot validation failed: " .. validator.name)
        end
    end
    return true
end

function Host:createWorld(stage_id)
    local stage = self.catalog:get(stage_id)
    if not stage or stage.kind ~= "stage" then
        return nil, "missing stage '" .. tostring(stage_id) .. "'"
    end

    local world = World.new(self, stage)
    local loaded, load_error = world:load()
    if not loaded then return nil, load_error end
    return world
end

return Host

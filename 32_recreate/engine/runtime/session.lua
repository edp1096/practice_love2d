local util = require "engine.core.util"

local Session = {}
Session.__index = Session

local function positiveInteger(value)
    return type(value) == "number" and
        value >= 1 and value % 1 == 0
end

local function sectionError(name, message)
    error(
        string.format("session section '%s': %s", name, message),
        3
    )
end

function Session.new(store)
    assert(type(store) == "table", "session store must be a table")
    assert(type(store.values) == "table", "session values must be a table")
    assert(
        type(store.versions) == "table",
        "session versions must be a table"
    )
    return setmetatable({
        store = store,
        values = store.values,
        versions = store.versions,
        sections = {},
    }, Session)
end

function Session:registerSection(name, definition)
    assert(
        type(name) == "string" and name ~= "",
        "session section name is required"
    )
    assert(
        type(definition) == "table",
        "session section definition is required"
    )
    assert(
        positiveInteger(definition.version),
        "session section version must be a positive integer"
    )
    assert(
        definition.defaults == nil or
            type(definition.defaults) == "table",
        "session section defaults must be a table"
    )
    assert(
        definition.migrations == nil or
            type(definition.migrations) == "table",
        "session section migrations must be a table"
    )
    assert(
        definition.validate == nil or
            type(definition.validate) == "function",
        "session section validate must be a function"
    )
    assert(
        not self.sections[name],
        "duplicate session section: " .. name
    )

    local current_version = definition.version
    local value = self.values[name]
    local stored_version = self.versions[name]
    if value == nil then
        if stored_version ~= nil then
            sectionError(name, "has a version but no data")
        end
        value = util.deepCopy(definition.defaults or {})
        stored_version = current_version
    else
        if type(value) ~= "table" then
            sectionError(name, "data must be a table")
        end
        -- Live sessions created before section version tracking contain data
        -- but no version. They already match the running code, so treat them
        -- as current. Serialized saves always carry an explicit version.
        if stored_version == nil then stored_version = current_version end
        if not positiveInteger(stored_version) then
            sectionError(name, "version must be a positive integer")
        end
    end
    if stored_version > current_version then
        sectionError(
            name,
            string.format(
                "version %d is newer than supported version %d",
                stored_version,
                current_version
            )
        )
    end

    local candidate = util.deepCopy(value)
    while stored_version < current_version do
        local migration =
            definition.migrations and
            definition.migrations[stored_version]
        if type(migration) ~= "function" then
            sectionError(
                name,
                string.format(
                    "has no migration from version %d to %d",
                    stored_version,
                    stored_version + 1
                )
            )
        end
        local migrated, result, migration_error =
            pcall(migration, candidate)
        if not migrated then sectionError(name, tostring(result)) end
        if type(result) ~= "table" then
            sectionError(
                name,
                migration_error or
                    string.format(
                        "migration from version %d did not return a table",
                        stored_version
                    )
            )
        end
        candidate = result
        stored_version = stored_version + 1
    end

    if definition.validate then
        local called, valid, validation_error =
            pcall(definition.validate, candidate)
        if not called then sectionError(name, tostring(valid)) end
        if valid ~= true then
            sectionError(
                name,
                validation_error or "failed validation"
            )
        end
    end

    self.values[name] = candidate
    self.versions[name] = current_version
    self.sections[name] = definition
    return candidate
end

function Session:namespace(name, defaults)
    return self:registerSection(name, {
        version = 1,
        defaults = defaults or {},
        validate = function(value)
            if type(value) ~= "table" then
                return nil, "data must be a table"
            end
            return true
        end,
    })
end

function Session:peek(name)
    return self.values[name]
end

function Session:validateKnown()
    for name in pairs(self.values) do
        if not self.sections[name] then
            return nil, "save contains unknown session section '" ..
                tostring(name) .. "'"
        end
    end
    for name in pairs(self.versions) do
        if not self.sections[name] then
            return nil, "save contains unknown session version '" ..
                tostring(name) .. "'"
        end
        if self.values[name] == nil then
            return nil, "session section '" .. tostring(name) ..
                "' has a version but no data"
        end
    end
    return true
end

function Session:exportSections()
    local known, known_error = self:validateKnown()
    if not known then return nil, known_error end
    local result = {}
    for _, name in ipairs(util.sortedKeys(self.sections)) do
        result[name] = {
            version = self.versions[name],
            data = util.deepCopy(self.values[name]),
        }
    end
    return result
end

function Session:inspect()
    local versions = {}
    for _, name in ipairs(util.sortedKeys(self.sections)) do
        versions[name] = self.versions[name]
    end
    return {
        session_namespaces = util.sortedKeys(self.sections),
        session_versions = versions,
    }
end

return Session

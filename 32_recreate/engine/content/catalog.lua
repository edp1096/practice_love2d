local util = require "engine.core.util"
local Validator = require "engine.content.validator"

local Catalog = {}
Catalog.__index = Catalog

local id_pattern = "^[a-z][a-z0-9_]*%.[a-z][a-z0-9_.-]*$"

local function inspectPureData(value, path, seen, errors)
    local value_type = type(value)
    if value_type == "nil" or value_type == "boolean" or
       value_type == "number" or value_type == "string" then
        return
    end
    if value_type ~= "table" then
        errors[#errors + 1] =
            path .. " contains forbidden " .. value_type .. " value"
        return
    end
    if getmetatable(value) ~= nil then
        errors[#errors + 1] = path .. " must not have a metatable"
        return
    end
    if seen[value] then
        errors[#errors + 1] = path .. " contains a table cycle"
        return
    end

    seen[value] = true
    local key_kind = nil
    for key, item in pairs(value) do
        local current_kind = type(key)
        if current_kind ~= "string" and current_kind ~= "number" then
            errors[#errors + 1] =
                path .. " contains a forbidden " .. current_kind .. " key"
        else
            if key_kind and key_kind ~= current_kind then
                errors[#errors + 1] =
                    path .. " must not mix string and numeric keys"
            end
            key_kind = key_kind or current_kind
            inspectPureData(
                item,
                string.format("%s[%s]", path, tostring(key)),
                seen,
                errors
            )
        end
    end
    seen[value] = nil
end

local function discover(filesystem, root, output)
    local items, list_error = filesystem:list(root)
    if not items then
        return nil, list_error or ("could not list " .. root)
    end
    table.sort(items)

    for _, name in ipairs(items) do
        local path = root .. "/" .. name
        local info = filesystem:info(path)
        if info and info.type == "directory" then
            local ok, child_error = discover(filesystem, path, output)
            if not ok then return nil, child_error end
        elseif info and info.type == "file" and
               name:sub(-4) == ".lua" and
               name:sub(1, 1) ~= "_" and
               name ~= "init.lua" then
            output[#output + 1] = path
        end
    end
    return output
end

function Catalog.new(filesystem)
    return setmetatable({
        filesystem = filesystem,
        definitions = {},
        by_kind = {},
        sources = {},
        load_errors = {},
        references = {},
    }, Catalog)
end

function Catalog:_add(definition, source)
    local data_errors = {}
    inspectPureData(definition, "content", {}, data_errors)
    for _, message in ipairs(data_errors) do
        self.load_errors[#self.load_errors + 1] =
            source .. ": " .. message
    end
    if #data_errors > 0 then return end

    if type(definition) ~= "table" then
        self.load_errors[#self.load_errors + 1] =
            source .. ": content file must return a table"
        return
    end
    if definition.schema_version ~= 1 then
        self.load_errors[#self.load_errors + 1] =
            source .. ": schema_version must be 1"
        return
    end
    if type(definition.kind) ~= "string" or definition.kind == "" then
        self.load_errors[#self.load_errors + 1] =
            source .. ": kind must be a non-empty string"
        return
    end
    if type(definition.id) ~= "string" or
       not definition.id:match(id_pattern) then
        self.load_errors[#self.load_errors + 1] =
            source .. ": id must match namespace.name using lowercase characters"
        return
    end
    if self.definitions[definition.id] then
        self.load_errors[#self.load_errors + 1] = string.format(
            "%s: duplicate id '%s' (already declared in %s)",
            source,
            definition.id,
            self.sources[definition.id]
        )
        return
    end

    self.definitions[definition.id] = definition
    self.sources[definition.id] = source
    self.by_kind[definition.kind] = self.by_kind[definition.kind] or {}
    self.by_kind[definition.kind][definition.id] = definition
end

function Catalog:loadRoots(roots)
    for _, root in ipairs(roots or {}) do
        local paths = {}
        local discovered, discover_error =
            discover(self.filesystem, root, paths)
        if not discovered then
            self.load_errors[#self.load_errors + 1] =
                root .. ": " .. tostring(discover_error)
        else
            for _, path in ipairs(discovered) do
                local definition, load_error = self.filesystem:loadTable(path)
                if definition then
                    self:_add(definition, path)
                else
                    self.load_errors[#self.load_errors + 1] =
                        path .. ": " .. tostring(load_error)
                end
            end
        end
    end
end

function Catalog:addForTest(definition, source)
    self:_add(util.deepCopy(definition), source or "<test>")
end

function Catalog:get(id)
    return self.definitions[id]
end

function Catalog:recordReference(source_id, target_id, path)
    if source_id == target_id then return end
    local entries = self.references[source_id]
    if not entries then
        entries = {}
        self.references[source_id] = entries
    end
    local key = target_id .. "\0" .. path
    for _, entry in ipairs(entries) do
        if entry.key == key then return end
    end
    entries[#entries + 1] = {
        key = key,
        id = target_id,
        path = path,
    }
end

function Catalog:all(kind)
    local source = kind and self.by_kind[kind] or self.definitions
    local result = {}
    for _, id in ipairs(util.sortedKeys(source)) do
        result[#result + 1] = source[id]
    end
    return result
end

function Catalog:validate(host)
    self.references = {}
    local validator = Validator.new(self, host)
    for _, error_message in ipairs(self.load_errors) do
        validator.errors[#validator.errors + 1] = error_message
    end

    for _, definition in ipairs(self:all()) do
        validator:setDefinition(
            definition.id,
            self.sources[definition.id]
        )
        local kind = host.content_kinds[definition.kind]
        if not kind then
            validator:error(
                "kind",
                "unknown content kind '" .. definition.kind .. "'"
            )
        else
            kind.validate(definition, validator, host)
        end
    end
    return validator:finish()
end

function Catalog:dependencyGraph()
    local dependents = {}
    local edge_count = 0
    for source_id, entries in pairs(self.references) do
        table.sort(entries, function(left, right)
            if left.id ~= right.id then return left.id < right.id end
            return left.path < right.path
        end)
        for _, entry in ipairs(entries) do
            local reverse = dependents[entry.id] or {}
            reverse[#reverse + 1] = {
                id = source_id,
                path = entry.path,
            }
            dependents[entry.id] = reverse
            edge_count = edge_count + 1
        end
    end

    local nodes = {}
    for _, definition in ipairs(self:all()) do
        local dependencies = {}
        for _, entry in ipairs(
            self.references[definition.id] or {}
        ) do
            dependencies[#dependencies + 1] = {
                id = entry.id,
                path = entry.path,
            }
        end
        local reverse = dependents[definition.id] or {}
        table.sort(reverse, function(left, right)
            if left.id ~= right.id then return left.id < right.id end
            return left.path < right.path
        end)
        nodes[#nodes + 1] = {
            id = definition.id,
            kind = definition.kind,
            source = self.sources[definition.id],
            asset_path =
                definition.kind == "asset" and definition.path or nil,
            dependencies = dependencies,
            dependents = reverse,
        }
    end
    return {
        total = #nodes,
        edge_count = edge_count,
        nodes = nodes,
    }
end

function Catalog:summary()
    local kinds = {}
    local total = 0
    for kind, definitions in pairs(self.by_kind) do
        local count = 0
        for _ in pairs(definitions) do count = count + 1 end
        kinds[kind] = count
        total = total + count
    end
    return {total = total, kinds = kinds}
end

return Catalog

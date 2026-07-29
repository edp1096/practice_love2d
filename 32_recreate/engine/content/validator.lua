local Validator = {}
Validator.__index = Validator

function Validator.new(catalog, host)
    return setmetatable({
        catalog = catalog,
        host = host,
        errors = {},
        source = "<unknown>",
        definition_id = nil,
    }, Validator)
end

function Validator:setSource(source)
    self.source = source or "<unknown>"
    self.definition_id = nil
end

function Validator:setDefinition(definition_id, source)
    self.definition_id = definition_id
    self.source = source or "<unknown>"
end

function Validator:error(path, message)
    self.errors[#self.errors + 1] =
        string.format("%s: %s: %s", self.source, path, message)
end

function Validator:string(value, path, required)
    if value == nil then
        if required then self:error(path, "is required") end
        return nil
    end
    if type(value) ~= "string" or value == "" then
        self:error(path, "must be a non-empty string")
        return nil
    end
    return value
end

function Validator:number(value, path, required)
    if value == nil then
        if required then self:error(path, "is required") end
        return nil
    end
    if type(value) ~= "number" or value ~= value or
       value == math.huge or value == -math.huge then
        self:error(path, "must be a finite number")
        return nil
    end
    return value
end

function Validator:boolean(value, path, required)
    if value == nil then
        if required then self:error(path, "is required") end
        return nil
    end
    if type(value) ~= "boolean" then
        self:error(path, "must be a boolean")
        return nil
    end
    return value
end

function Validator:table(value, path, required)
    if value == nil then
        if required then self:error(path, "is required") end
        return nil
    end
    if type(value) ~= "table" then
        self:error(path, "must be a table")
        return nil
    end
    return value
end

function Validator:array(value, path, required)
    if not self:table(value, path, required) then return nil end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            self:error(path, "must use consecutive numeric indexes")
            return nil
        end
        count = count + 1
    end
    for index = 1, count do
        if value[index] == nil then
            self:error(path, "must not contain index gaps")
            return nil
        end
    end
    return value
end

function Validator:enum(value, allowed, path, required)
    value = self:string(value, path, required)
    if not value then return nil end
    for _, candidate in ipairs(allowed) do
        if candidate == value then return value end
    end
    self:error(path, "must be one of: " .. table.concat(allowed, ", "))
    return nil
end

function Validator:positive(value, path, required)
    value = self:number(value, path, required)
    if value and value <= 0 then
        self:error(path, "must be greater than zero")
        return nil
    end
    return value
end

function Validator:keys(value, allowed, path)
    if type(value) ~= "table" then return end
    local allowed_set = {}
    for _, key in ipairs(allowed) do allowed_set[key] = true end
    for key in pairs(value) do
        if type(key) ~= "string" then
            self:error(
                string.format("%s[%s]", path, tostring(key)),
                "object fields must use string keys"
            )
        elseif not allowed_set[key] then
            self:error(
                path .. "." .. key,
                "is not a recognized field"
            )
        end
    end
end

function Validator:reference(value, kind, path)
    value = self:string(value, path, true)
    if not value then return nil end

    local target = self.catalog:get(value)
    if not target then
        self:error(path, "references missing content '" .. value .. "'")
        return nil
    end
    if target.kind ~= kind then
        self:error(
            path,
            string.format(
                "references '%s' of kind '%s', expected '%s'",
                value,
                target.kind,
                kind
            )
        )
        return nil
    end
    if self.definition_id then
        self.catalog:recordReference(
            self.definition_id,
            target.id,
            path
        )
    end
    return target
end

function Validator:finish()
    table.sort(self.errors)
    return #self.errors == 0, self.errors
end

return Validator

local Rules = {}
Rules.__index = Rules

function Rules.new()
    local self = setmetatable({
        actions = {},
        conditions = {},
        interceptors = {},
    }, Rules)

    self:registerCondition("always", {
        evaluate = function()
            return true
        end,
    })
    self:registerCondition("all", {
        validate = function(condition, validator, path, rules)
            local conditions = validator:array(
                condition.conditions,
                path .. ".conditions",
                true
            )
            for index, child in ipairs(conditions or {}) do
                rules:validateCondition(
                    child,
                    validator,
                    string.format("%s.conditions[%d]", path, index)
                )
            end
        end,
        evaluate = function(condition, context, rules)
            for _, child in ipairs(condition.conditions or {}) do
                if not rules:evaluate(child, context) then return false end
            end
            return true
        end,
    })
    self:registerCondition("any", {
        validate = function(condition, validator, path, rules)
            local conditions = validator:array(
                condition.conditions,
                path .. ".conditions",
                true
            )
            for index, child in ipairs(conditions or {}) do
                rules:validateCondition(
                    child,
                    validator,
                    string.format("%s.conditions[%d]", path, index)
                )
            end
        end,
        evaluate = function(condition, context, rules)
            for _, child in ipairs(condition.conditions or {}) do
                if rules:evaluate(child, context) then return true end
            end
            return false
        end,
    })
    self:registerCondition("not", {
        validate = function(condition, validator, path, rules)
            if validator:table(condition.condition, path .. ".condition", true) then
                rules:validateCondition(
                    condition.condition,
                    validator,
                    path .. ".condition"
                )
            end
        end,
        evaluate = function(condition, context, rules)
            return not rules:evaluate(condition.condition, context)
        end,
    })

    return self
end

function Rules:registerActionInterceptor(
    action_type,
    name,
    priority,
    handler
)
    assert(type(action_type) == "string", "interceptor action type is required")
    assert(type(name) == "string" and name ~= "", "interceptor name is required")
    assert(type(handler) == "function", "interceptor handler is required")

    local interceptors = self.interceptors[action_type] or {}
    for _, existing in ipairs(interceptors) do
        assert(existing.name ~= name, "duplicate action interceptor: " .. name)
    end
    interceptors[#interceptors + 1] = {
        name = name,
        priority = priority or 100,
        handler = handler,
    }
    table.sort(interceptors, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end
        return left.name < right.name
    end)
    self.interceptors[action_type] = interceptors
end

local function register(registry, kind, name, definition)
    assert(type(name) == "string" and name ~= "", kind .. " name is required")
    assert(type(definition) == "table", kind .. " definition must be a table")
    assert(not registry[name], "duplicate " .. kind .. ": " .. name)
    registry[name] = definition
end

function Rules:registerAction(name, definition)
    register(self.actions, "action", name, definition)
end

function Rules:registerCondition(name, definition)
    register(self.conditions, "condition", name, definition)
end

function Rules:validateAction(action, validator, path)
    if not validator:table(action, path, true) then return end
    local action_type = validator:string(action.type, path .. ".type", true)
    if not action_type then return end

    local definition = self.actions[action_type]
    if not definition then
        validator:error(path .. ".type", "unknown action '" .. action_type .. "'")
        return
    end
    if definition.validate then
        definition.validate(action, validator, path, self)
    end
end

function Rules:validateCondition(condition, validator, path)
    if not validator:table(condition, path, true) then return end
    local condition_type =
        validator:string(condition.type, path .. ".type", true)
    if not condition_type then return end

    local definition = self.conditions[condition_type]
    if not definition then
        validator:error(
            path .. ".type",
            "unknown condition '" .. condition_type .. "'"
        )
        return
    end
    if definition.validate then
        definition.validate(condition, validator, path, self)
    end
end

function Rules:execute(action, context)
    local definition = self.actions[action.type]
    if not definition then
        return nil, "unknown action '" .. tostring(action.type) .. "'"
    end
    context = context or {}
    local interceptors = self.interceptors[action.type] or {}

    local function invoke(index, current_action, current_context)
        local interceptor = interceptors[index]
        if interceptor then
            local next_called = false
            local function nextHandler(next_action, next_context)
                assert(
                    not next_called,
                    "action interceptor called next() more than once: " ..
                        interceptor.name
                )
                next_called = true
                return invoke(
                    index + 1,
                    next_action or current_action,
                    next_context or current_context
                )
            end
            return interceptor.handler(
                current_action,
                current_context,
                nextHandler,
                self
            )
        end
        return definition.execute(
            current_action,
            current_context,
            self
        )
    end

    return invoke(1, action, context)
end

function Rules:evaluate(condition, context)
    condition = condition or {type = "always"}
    local definition = self.conditions[condition.type]
    if not definition then
        return false, "unknown condition '" .. tostring(condition.type) .. "'"
    end
    return definition.evaluate(condition, context or {}, self)
end

return Rules

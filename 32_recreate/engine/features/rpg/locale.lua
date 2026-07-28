local Schema = require "engine.runtime.session_schema"

local feature = {
    id = "rpg.locale",
    requires = {"engine.features.session"},
}

local function validateLocale(definition, validator)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name",
            "code", "strings",
        },
        "content"
    )
    validator:string(definition.name, "name", false)
    local code = validator:string(definition.code, "code", true)
    local strings = validator:table(
        definition.strings,
        "strings",
        true
    )
    local count = 0
    for key, value in pairs(strings or {}) do
        count = count + 1
        if type(key) ~= "string" or key == "" then
            validator:error(
                "strings",
                "translation keys must be non-empty strings"
            )
        else
            validator:string(
                value,
                "strings." .. key,
                true
            )
        end
    end
    if strings and count == 0 then
        validator:error("strings", "must not be empty")
    end

    if code then
        for _, other in ipairs(validator.catalog:all()) do
            if other ~= definition and other.kind == "locale" and
               other.code == code and other.id < definition.id then
                validator:error(
                    "code",
                    "duplicates locale code from '" .. other.id .. "'"
                )
                break
            end
        end
    end
end

function feature:register(host)
    local config = host.manifest.locale or {}
    local session = host.services.session
    local state = session:registerSection("rpg.locale", {
        version = 1,
        defaults = {selected = config.default},
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "rpg.locale",
                {"selected"},
                {}
            )
            if not valid then return nil, value_error end
            return Schema.optionalString(
                value.selected,
                "rpg.locale.selected"
            )
        end,
    })
    local locale = {}

    local function definition(locale_id)
        local value = locale_id and host.catalog:get(locale_id)
        if value and value.kind == "locale" then return value end
        return nil
    end

    function locale:id()
        if definition(state.selected) then return state.selected end
        if definition(config.default) then
            state.selected = config.default
            return state.selected
        end
        for _, value in ipairs(host.catalog:all()) do
            if value.kind == "locale" then
                state.selected = value.id
                return state.selected
            end
        end
        return nil
    end

    function locale:code()
        local value = definition(self:id())
        return value and value.code or nil
    end

    function locale:text(key, fallback)
        local selected = definition(self:id())
        local value = selected and selected.strings[key]
        if value ~= nil then return value end
        local fallback_locale = definition(config.fallback)
        value = fallback_locale and fallback_locale.strings[key]
        if value ~= nil then return value end
        return fallback or key
    end

    function locale:set(world, locale_id)
        local value = definition(locale_id)
        if not value then
            return nil, "unknown locale '" .. tostring(locale_id) .. "'"
        end
        local previous = self:id()
        state.selected = locale_id
        if previous ~= locale_id and world then
            world.events:emit("locale.changed", {
                locale_id = locale_id,
                code = value.code,
                previous = previous,
            })
        end
        return {
            applied = previous ~= locale_id,
            locale_id = locale_id,
            code = value.code,
            previous = previous,
        }
    end

    host:registerContentKind("locale", {
        validate = validateLocale,
    })
    host.rules:registerAction("set_locale", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "locale"}, path)
            validator:reference(
                action.locale,
                "locale",
                path .. ".locale"
            )
        end,
        execute = function(action, context)
            return locale:set(context.world, action.locale)
        end,
    })
    host.rules:registerCondition("locale_is", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "locale"}, path)
            validator:reference(
                condition.locale,
                "locale",
                path .. ".locale"
            )
        end,
        evaluate = function(condition)
            return locale:id() == condition.locale
        end,
    })

    host:registerBootValidator(
        "rpg.locale",
        function()
            if state.selected and not definition(state.selected) then
                return nil, "locale save references missing content '" ..
                    tostring(state.selected) .. "'"
            end
            if not locale:id() then
                return nil, "rpg.locale needs at least one locale content"
            end
            if config.fallback and not definition(config.fallback) then
                return nil, "locale fallback references missing content '" ..
                    tostring(config.fallback) .. "'"
            end
            return true
        end
    )
    host:registerService("locale", locale)
    host:registerWorldInspector("rpg.locale", function()
        return {
            locale = {
                id = locale:id(),
                code = locale:code(),
                fallback = config.fallback,
            },
        }
    end)
end

return feature

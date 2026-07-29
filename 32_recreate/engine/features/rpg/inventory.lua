local util = require "engine.core.util"
local Schema = require "engine.runtime.session_schema"

local feature = {
    id = "rpg.inventory",
    requires = {"engine.features.session"},
}

local function positiveInteger(value, validator, path, required)
    value = validator:number(value, path, required)
    if value and (value < 1 or value % 1 ~= 0) then
        validator:error(path, "must be a positive integer")
        return nil
    end
    return value
end

local function nonNegativeInteger(value, validator, path)
    value = validator:number(value, path, false)
    if value and (value < 0 or value % 1 ~= 0) then
        validator:error(path, "must be a non-negative integer")
        return nil
    end
    return value
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
    return actions
end

function feature:register(host)
    local session = host.services.session
    local state = session:registerSection("rpg.inventory", {
        version = 1,
        defaults = {counts = {}},
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "rpg.inventory",
                {"counts"},
                {"counts"}
            )
            if not valid then return nil, value_error end
            return Schema.map(
                value.counts,
                "rpg.inventory.counts",
                function(count, path)
                    return Schema.positiveInteger(count, path)
                end
            )
        end,
    })
    local item_sections = {}
    local item_section_order = {}
    local removal_guards = {}
    local inventory = {}

    function inventory:registerItemSection(name, definition)
        assert(
            type(name) == "string" and name ~= "",
            "item section name is required"
        )
        assert(
            type(definition) == "table" and
                type(definition.validate) == "function",
            "item section validator is required"
        )
        assert(not item_sections[name], "duplicate item section: " .. name)
        item_sections[name] = definition
        item_section_order[#item_section_order + 1] = name
        table.sort(item_section_order)
    end

    function inventory:registerRemovalGuard(name, handler)
        assert(
            type(name) == "string" and name ~= "",
            "inventory removal guard name is required"
        )
        assert(
            type(handler) == "function",
            "inventory removal guard handler is required"
        )
        for _, guard in ipairs(removal_guards) do
            assert(
                guard.name ~= name,
                "duplicate inventory removal guard: " .. name
            )
        end
        removal_guards[#removal_guards + 1] = {
            name = name,
            handler = handler,
        }
        table.sort(removal_guards, function(left, right)
            return left.name < right.name
        end)
    end

    local function itemDefinition(item_id)
        local definition = host.catalog:get(item_id)
        if definition and definition.kind == "item" then
            return definition
        end
        return nil
    end

    function inventory:count(item_id)
        return state.counts[item_id] or 0
    end

    function inventory:give(world, item_id, amount)
        amount = amount or 1
        local definition = itemDefinition(item_id)
        if not definition then
            return nil, "unknown item '" .. tostring(item_id) .. "'"
        end
        if type(amount) ~= "number" or
           amount < 1 or amount % 1 ~= 0 then
            return nil, "item amount must be a positive integer"
        end
        local previous = self:count(item_id)
        local maximum = definition.stack_limit or 99
        if previous + amount > maximum then
            return nil, string.format(
                "item '%s' would exceed stack limit %d",
                item_id,
                maximum
            )
        end
        state.counts[item_id] = previous + amount
        if world then
            world.events:emit("inventory.item_added", {
                item_id = item_id,
                amount = amount,
                count = state.counts[item_id],
            })
        end
        return {
            applied = true,
            item_id = item_id,
            amount = amount,
            count = state.counts[item_id],
        }
    end

    function inventory:take(world, item_id, amount)
        amount = amount or 1
        local definition = itemDefinition(item_id)
        if not definition then
            return nil, "unknown item '" .. tostring(item_id) .. "'"
        end
        if type(amount) ~= "number" or
           amount < 1 or amount % 1 ~= 0 then
            return nil, "item amount must be a positive integer"
        end
        local previous = self:count(item_id)
        if previous < amount then
            return nil, string.format(
                "not enough item '%s': have %d, need %d",
                item_id,
                previous,
                amount
            )
        end
        for _, guard in ipairs(removal_guards) do
            local allowed, reason = guard.handler(
                item_id,
                amount,
                previous,
                definition
            )
            if allowed == false then
                return nil, reason or
                    ("item removal blocked by " .. guard.name)
            end
        end
        local count = previous - amount
        state.counts[item_id] = count > 0 and count or nil
        if world then
            world.events:emit("inventory.item_removed", {
                item_id = item_id,
                amount = amount,
                count = count,
            })
        end
        return {
            applied = true,
            item_id = item_id,
            amount = amount,
            count = count,
        }
    end

    function inventory:use(world, item_id, target, source)
        local definition = itemDefinition(item_id)
        if not definition then
            return nil, "unknown item '" .. tostring(item_id) .. "'"
        end
        if not definition.consumable then
            return nil, "item '" .. item_id .. "' is not consumable"
        end
        if self:count(item_id) < 1 then
            return nil, "item '" .. item_id .. "' is not in inventory"
        end
        target = target or world:findByTag("player")[1]
        return world:transaction(function()
            local effects, effect_error = world:executeActions(
                definition.effects,
                {
                source = source or target,
                target = target,
                item = definition,
                }
            )
            if not effects then
                return nil, "item effects failed: " ..
                    tostring(effect_error)
            end
            local removed, remove_error = self:take(world, item_id, 1)
            if not removed then return nil, remove_error end
            world.events:emit("inventory.item_used", {
                item_id = item_id,
                target_id = target and target.id or nil,
                count = self:count(item_id),
            })
            return {
                applied = true,
                item_id = item_id,
                count = self:count(item_id),
            }
        end)
    end

    host:registerContentKind("item", {
        validate = function(definition, validator)
            local allowed = {
                "schema_version", "kind", "id", "name", "name_key",
                "description", "description_key", "stack_limit",
                "consumable", "effects", "value",
            }
            for _, name in ipairs(item_section_order) do
                allowed[#allowed + 1] = name
            end
            validator:keys(definition, allowed, "content")
            local name = validator:string(
                definition.name,
                "name",
                false
            )
            local name_key = validator:string(
                definition.name_key,
                "name_key",
                false
            )
            if not name and not name_key then
                validator:error(
                    "name",
                    "requires name or name_key"
                )
            end
            validator:string(
                definition.description,
                "description",
                false
            )
            validator:string(
                definition.description_key,
                "description_key",
                false
            )
            positiveInteger(
                definition.stack_limit,
                validator,
                "stack_limit",
                false
            )
            local consumable = validator:boolean(
                definition.consumable,
                "consumable",
                false
            )
            local effects = validateActions(
                definition.effects,
                validator,
                host,
                "effects"
            )
            if consumable and (not effects or #effects == 0) then
                validator:error(
                    "effects",
                    "consumable items require at least one effect"
                )
            elseif effects and not consumable then
                validator:error(
                    "effects",
                    "requires consumable = true"
                )
            end
            nonNegativeInteger(definition.value, validator, "value")
            for _, section_name in ipairs(item_section_order) do
                local section = definition[section_name]
                if section ~= nil then
                    item_sections[section_name].validate(
                        section,
                        validator,
                        section_name,
                        definition
                    )
                end
            end
        end,
    })

    local function validateItemAmount(action, validator, path)
        validator:keys(action, {"type", "item", "amount"}, path)
        validator:reference(action.item, "item", path .. ".item")
        positiveInteger(
            action.amount,
            validator,
            path .. ".amount",
            false
        )
    end

    host.rules:registerAction("give_item", {
        validate = validateItemAmount,
        execute = function(action, context)
            return inventory:give(
                context.world,
                action.item,
                action.amount
            )
        end,
    })
    host.rules:registerAction("take_item", {
        validate = validateItemAmount,
        execute = function(action, context)
            return inventory:take(
                context.world,
                action.item,
                action.amount
            )
        end,
    })
    host.rules:registerAction("use_item", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "item"}, path)
            validator:reference(
                action.item,
                "item",
                path .. ".item"
            )
        end,
        execute = function(action, context)
            return inventory:use(
                context.world,
                action.item,
                context.target,
                context.source
            )
        end,
    })
    host.rules:registerCondition("has_item", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "item", "amount"},
                path
            )
            validator:reference(
                condition.item,
                "item",
                path .. ".item"
            )
            positiveInteger(
                condition.amount,
                validator,
                path .. ".amount",
                false
            )
        end,
        evaluate = function(condition)
            return inventory:count(condition.item) >=
                (condition.amount or 1)
        end,
    })

    host:registerBootValidator("rpg.inventory.session", function()
        for item_id, count in pairs(state.counts) do
            local item = itemDefinition(item_id)
            if not item then
                return nil, "inventory save references missing item '" ..
                    item_id .. "'"
            end
            local maximum = item.stack_limit or 99
            if count > maximum then
                return nil, string.format(
                    "inventory save has %d of '%s', above stack limit %d",
                    count,
                    item_id,
                    maximum
                )
            end
        end
        return true
    end)

    host:registerService("inventory", inventory)
    host:registerWorldInspector("rpg.inventory", function(world)
        local entries = {}
        local total = 0
        local locale = world:service("locale")
        for _, item_id in ipairs(util.sortedKeys(state.counts)) do
            local count = state.counts[item_id]
            local definition = itemDefinition(item_id)
            entries[#entries + 1] = {
                item_id = item_id,
                count = count,
                name = definition and
                    (locale and definition.name_key and
                        locale:text(
                            definition.name_key,
                            definition.name
                        ) or definition.name) or item_id,
            }
            total = total + count
        end
        return {
            inventory = entries,
            inventory_distinct = #entries,
            inventory_total = total,
        }
    end)
end

return feature

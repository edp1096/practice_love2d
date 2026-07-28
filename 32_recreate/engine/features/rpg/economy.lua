local Schema = require "engine.runtime.session_schema"

local feature = {
    id = "rpg.economy",
    requires = {"engine.features.session"},
}

local function nonNegativeInteger(value, validator, path, required)
    value = validator:number(value, path, required)
    if value and (value < 0 or value % 1 ~= 0) then
        validator:error(path, "must be a non-negative integer")
        return nil
    end
    return value
end

function feature:register(host)
    local session = host.services.session
    local state = session:registerSection("rpg.economy", {
        version = 1,
        defaults = {balance = 0},
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "rpg.economy",
                {"balance"},
                {"balance"}
            )
            if not valid then return nil, value_error end
            return Schema.nonNegativeInteger(
                value.balance,
                "rpg.economy.balance"
            )
        end,
    })
    local economy = {}

    function economy:balance()
        return state.balance
    end

    function economy:add(world, amount, reason)
        if type(amount) ~= "number" or
           amount < 0 or amount % 1 ~= 0 then
            return nil, "currency amount must be a non-negative integer"
        end
        local previous = state.balance
        state.balance = state.balance + amount
        if world and amount > 0 then
            world.events:emit("economy.currency_added", {
                amount = amount,
                balance = state.balance,
                previous = previous,
                reason = reason,
            })
        end
        return {
            applied = amount > 0,
            amount = amount,
            balance = state.balance,
            previous = previous,
        }
    end

    function economy:spend(world, amount, reason)
        if type(amount) ~= "number" or
           amount < 0 or amount % 1 ~= 0 then
            return nil, "currency amount must be a non-negative integer"
        end
        if state.balance < amount then
            return nil, string.format(
                "not enough currency: have %d, need %d",
                state.balance,
                amount
            )
        end
        local previous = state.balance
        state.balance = state.balance - amount
        if world and amount > 0 then
            world.events:emit("economy.currency_spent", {
                amount = amount,
                balance = state.balance,
                previous = previous,
                reason = reason,
            })
        end
        return {
            applied = amount > 0,
            amount = amount,
            balance = state.balance,
            previous = previous,
        }
    end

    host.rules:registerAction("add_currency", {
        validate = function(action, validator, path)
            validator:keys(
                action,
                {"type", "amount", "reason"},
                path
            )
            nonNegativeInteger(
                action.amount,
                validator,
                path .. ".amount",
                true
            )
            validator:string(
                action.reason,
                path .. ".reason",
                false
            )
        end,
        execute = function(action, context)
            return economy:add(
                context.world,
                action.amount,
                action.reason
            )
        end,
    })
    host.rules:registerAction("spend_currency", {
        validate = function(action, validator, path)
            validator:keys(
                action,
                {"type", "amount", "reason"},
                path
            )
            nonNegativeInteger(
                action.amount,
                validator,
                path .. ".amount",
                true
            )
            validator:string(
                action.reason,
                path .. ".reason",
                false
            )
        end,
        execute = function(action, context)
            return economy:spend(
                context.world,
                action.amount,
                action.reason
            )
        end,
    })
    host.rules:registerCondition("currency_at_least", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "amount"}, path)
            nonNegativeInteger(
                condition.amount,
                validator,
                path .. ".amount",
                true
            )
        end,
        evaluate = function(condition)
            return economy:balance() >= condition.amount
        end,
    })

    host:registerService("economy", economy)
    host:registerWorldInspector("rpg.economy", function()
        return {
            currency = {
                balance = economy:balance(),
            },
        }
    end)
end

return feature

local util = require "engine.core.util"

local feature = {
    id = "rpg.shop",
    requires = {
        "engine.features.rpg.economy",
        "engine.features.rpg.inventory",
        "engine.features.rpg.locale",
        "engine.features.control",
    },
}

local function nonNegativeInteger(value, validator, path, required)
    value = validator:number(value, path, required)
    if value and (value < 0 or value % 1 ~= 0) then
        validator:error(path, "must be a non-negative integer")
        return nil
    end
    return value
end

local function positiveInteger(value, validator, path)
    value = validator:number(value, path, false)
    if value and (value < 1 or value % 1 ~= 0) then
        validator:error(path, "must be a positive integer")
        return nil
    end
    return value
end

local function validateShop(definition, validator)
    validator:keys(
        definition,
        {
            "schema_version", "kind", "id", "name", "name_key",
            "offers",
        },
        "content"
    )
    local name = validator:string(definition.name, "name", false)
    local name_key = validator:string(
        definition.name_key,
        "name_key",
        false
    )
    if not name and not name_key then
        validator:error("name", "requires name or name_key")
    end
    local offers = validator:array(
        definition.offers,
        "offers",
        true
    )
    if offers and #offers == 0 then
        validator:error("offers", "must contain at least one offer")
    end
    local seen = {}
    for index, offer in ipairs(offers or {}) do
        local path = string.format("offers[%d]", index)
        if validator:table(offer, path, true) then
            validator:keys(
                offer,
                {"item", "buy_price", "sell_price"},
                path
            )
            local item = validator:reference(
                offer.item,
                "item",
                path .. ".item"
            )
            if item and seen[item.id] then
                validator:error(
                    path .. ".item",
                    "duplicates another shop offer"
                )
            elseif item then
                seen[item.id] = true
            end
            local buy = nonNegativeInteger(
                offer.buy_price,
                validator,
                path .. ".buy_price",
                false
            )
            local sell = nonNegativeInteger(
                offer.sell_price,
                validator,
                path .. ".sell_price",
                false
            )
            if buy == nil and sell == nil then
                validator:error(
                    path,
                    "requires buy_price or sell_price"
                )
            end
        end
    end
end

local function stateFor(world)
    local state = world.feature_state.shop
    if not state then
        state = {
            active = false,
            mode = "buy",
            selected = 1,
        }
        world.feature_state.shop = state
    end
    return state
end

function feature:register(host)
    for _, input_name in ipairs({
        "menu_up",
        "menu_down",
        "menu_left",
        "menu_right",
        "menu_confirm",
        "menu_cancel",
    }) do
        assert(
            host.input:hasAction(input_name),
            "rpg.shop requires input action '" .. input_name .. "'"
        )
    end

    local inventory = host.services.inventory
    local economy = host.services.economy
    local shop = {}

    local function definition(shop_id)
        local value = host.catalog:get(shop_id)
        if value and value.kind == "shop" then return value end
        return nil
    end

    local function offerFor(definition_value, item_id)
        for _, offer in ipairs(definition_value.offers) do
            if offer.item == item_id then return offer end
        end
        return nil
    end

    local function validQuantity(quantity)
        return type(quantity) == "number" and
            quantity >= 1 and quantity % 1 == 0
    end

    function shop:buy(world, shop_id, item_id, quantity)
        quantity = quantity or 1
        if not validQuantity(quantity) then
            return nil, "shop quantity must be a positive integer"
        end
        local definition_value = definition(shop_id)
        local offer = definition_value and
            offerFor(definition_value, item_id)
        if not offer or offer.buy_price == nil then
            return nil, "shop '" .. tostring(shop_id) ..
                "' does not sell item '" .. tostring(item_id) .. "'"
        end
        local item = host.catalog:get(item_id)
        local previous_count = inventory:count(item_id)
        if previous_count + quantity >
           (item.stack_limit or 99) then
            return nil, string.format(
                "item '%s' would exceed stack limit %d",
                item_id,
                item.stack_limit or 99
            )
        end
        local price = offer.buy_price * quantity
        local spent, spend_error = economy:spend(
            world,
            price,
            "shop.buy"
        )
        if not spent then return nil, spend_error end
        local added, add_error =
            inventory:give(world, item_id, quantity)
        if not added then
            economy:add(world, price, "shop.buy_rollback")
            return nil, add_error
        end
        world.events:emit("shop.item_bought", {
            shop_id = shop_id,
            item_id = item_id,
            quantity = quantity,
            price = price,
            balance = economy:balance(),
        })
        return {
            applied = true,
            shop_id = shop_id,
            item_id = item_id,
            quantity = quantity,
            price = price,
            balance = economy:balance(),
            count = inventory:count(item_id),
        }
    end

    function shop:sell(world, shop_id, item_id, quantity)
        quantity = quantity or 1
        if not validQuantity(quantity) then
            return nil, "shop quantity must be a positive integer"
        end
        local definition_value = definition(shop_id)
        local offer = definition_value and
            offerFor(definition_value, item_id)
        if not offer or offer.sell_price == nil then
            return nil, "shop '" .. tostring(shop_id) ..
                "' does not buy item '" .. tostring(item_id) .. "'"
        end
        local removed, remove_error =
            inventory:take(world, item_id, quantity)
        if not removed then return nil, remove_error end
        local price = offer.sell_price * quantity
        economy:add(world, price, "shop.sell")
        world.events:emit("shop.item_sold", {
            shop_id = shop_id,
            item_id = item_id,
            quantity = quantity,
            price = price,
            balance = economy:balance(),
        })
        return {
            applied = true,
            shop_id = shop_id,
            item_id = item_id,
            quantity = quantity,
            price = price,
            balance = economy:balance(),
            count = inventory:count(item_id),
        }
    end

    function shop:open(world, shop_id)
        local definition_value = definition(shop_id)
        if not definition_value then
            return nil, "unknown shop '" .. tostring(shop_id) .. "'"
        end
        local state = stateFor(world)
        if state.active then
            return nil, "another shop is already active"
        end
        state.active = true
        state.shop_id = shop_id
        state.mode = "buy"
        state.selected = 1
        state.message = nil
        state.opened_tick = world.ticks
        world.events:emit("shop.opened", {shop_id = shop_id})
        return {
            applied = true,
            shop_id = shop_id,
        }
    end

    function shop:close(world, reason)
        local state = stateFor(world)
        if not state.active then return {applied = false} end
        local shop_id = state.shop_id
        state.active = false
        state.shop_id = nil
        state.message = nil
        world.events:emit("shop.closed", {
            shop_id = shop_id,
            reason = reason or "closed",
        })
        return {
            applied = true,
            shop_id = shop_id,
        }
    end

    host:registerContentKind("shop", {
        validate = validateShop,
    })
    host.rules:registerAction("open_shop", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "shop"}, path)
            validator:reference(
                action.shop,
                "shop",
                path .. ".shop"
            )
        end,
        execute = function(action, context)
            return shop:open(context.world, action.shop)
        end,
    })
    host.rules:registerAction("close_shop", {
        validate = function(action, validator, path)
            validator:keys(action, {"type"}, path)
        end,
        execute = function(_, context)
            return shop:close(context.world, "action")
        end,
    })

    local function validateTrade(action, validator, path, field)
        validator:keys(
            action,
            {"type", "shop", "item", "quantity"},
            path
        )
        local definition_value = validator:reference(
            action.shop,
            "shop",
            path .. ".shop"
        )
        local item = validator:reference(
            action.item,
            "item",
            path .. ".item"
        )
        if definition_value and item then
            local offer = offerFor(definition_value, item.id)
            if not offer or offer[field] == nil then
                validator:error(
                    path .. ".item",
                    "is not available for this trade"
                )
            end
        end
        positiveInteger(
            action.quantity,
            validator,
            path .. ".quantity"
        )
    end

    host.rules:registerAction("buy_item", {
        validate = function(action, validator, path)
            validateTrade(action, validator, path, "buy_price")
        end,
        execute = function(action, context)
            return shop:buy(
                context.world,
                action.shop,
                action.item,
                action.quantity
            )
        end,
    })
    host.rules:registerAction("sell_item", {
        validate = function(action, validator, path)
            validateTrade(action, validator, path, "sell_price")
        end,
        execute = function(action, context)
            return shop:sell(
                context.world,
                action.shop,
                action.item,
                action.quantity
            )
        end,
    })
    host.rules:registerCondition("shop_active", {
        validate = function(condition, validator, path)
            validator:keys(condition, {"type", "shop"}, path)
            if condition.shop then
                validator:reference(
                    condition.shop,
                    "shop",
                    path .. ".shop"
                )
            end
        end,
        evaluate = function(condition, context)
            local state = context.world and
                stateFor(context.world) or nil
            return state ~= nil and state.active and
                (not condition.shop or state.shop_id == condition.shop)
        end,
    })

    host:registerWorldInitializer(
        "rpg.shop",
        95,
        function(world)
            stateFor(world)
            return true
        end
    )
    for _, channel in ipairs({"move", "act", "interact"}) do
        host:registerGate(
            channel,
            "rpg.shop",
            function(entity, world)
                if stateFor(world).active and entity.tag_set.player then
                    return false, "shop"
                end
                return true
            end
        )
    end

    local input_system = {
        id = "rpg.shop.input",
        phase = "input",
        order = 110,
    }
    function input_system:update(world)
        local state = stateFor(world)
        if not state.active or state.opened_tick == world.ticks then
            return
        end
        local definition_value = definition(state.shop_id)
        local input = host.input
        if input:wasPressed("menu_cancel") then
            shop:close(world, "cancelled")
            return
        end
        if input:wasPressed("menu_left") or
           input:wasPressed("menu_right") then
            state.mode = state.mode == "buy" and "sell" or "buy"
            state.selected = 1
            state.message = nil
        end
        local offer_count = #definition_value.offers
        if input:wasPressed("menu_up") then
            state.selected = state.selected - 1
            if state.selected < 1 then state.selected = offer_count end
        elseif input:wasPressed("menu_down") then
            state.selected = state.selected + 1
            if state.selected > offer_count then state.selected = 1 end
        end
        if input:wasPressed("menu_confirm") then
            local offer = definition_value.offers[state.selected]
            local result, trade_error
            if state.mode == "buy" then
                result, trade_error = shop:buy(
                    world,
                    state.shop_id,
                    offer.item,
                    1
                )
            else
                result, trade_error = shop:sell(
                    world,
                    state.shop_id,
                    offer.item,
                    1
                )
            end
            state.message = result and
                (state.mode == "buy" and "Purchased" or "Sold") or
                tostring(trade_error)
        end
    end

    local function localizedItemName(world, item_id)
        local item = host.catalog:get(item_id)
        local locale = world:service("locale")
        return item.name_key and
            locale:text(item.name_key, item.name) or item.name or item.id
    end

    local draw_system = {
        id = "rpg.shop.draw",
        draw_order = 310,
        draw_space = "screen",
    }
    function draw_system:draw(world)
        local state = stateFor(world)
        if not state.active then return end
        local definition_value = definition(state.shop_id)
        local locale = world:service("locale")
        local title = definition_value.name_key and
            locale:text(
                definition_value.name_key,
                definition_value.name
            ) or definition_value.name
        local view = world:view()
        local width, height = 560, 330
        local x = (view.width - width) / 2
        local y = (view.height - height) / 2
        love.graphics.setColor(0.015, 0.02, 0.035, 0.97)
        love.graphics.rectangle("fill", x, y, width, height, 10, 10)
        love.graphics.setColor(0.95, 0.72, 0.22, 1)
        love.graphics.rectangle("line", x, y, width, height, 10, 10)
        love.graphics.print(title, x + 20, y + 18)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(
            string.format(
                "[%s]   Currency: %d",
                state.mode:upper(),
                economy:balance()
            ),
            x + 20,
            y + 48,
            width - 40,
            "right"
        )
        for index, offer in ipairs(definition_value.offers) do
            local price = state.mode == "buy" and
                offer.buy_price or offer.sell_price
            local available = price ~= nil
            local selected = index == state.selected
            love.graphics.setColor(
                selected and 1 or (available and 0.8 or 0.38),
                selected and 0.85 or (available and 0.82 or 0.4),
                selected and 0.3 or (available and 0.88 or 0.45),
                1
            )
            love.graphics.print(
                (selected and "> " or "  ") ..
                    localizedItemName(world, offer.item),
                x + 28,
                y + 90 + (index - 1) * 30
            )
            love.graphics.printf(
                available and string.format(
                    "%d   (owned %d)",
                    price,
                    inventory:count(offer.item)
                ) or "--",
                x + 300,
                y + 90 + (index - 1) * 30,
                220,
                "right"
            )
        end
        if state.message then
            love.graphics.setColor(0.75, 0.9, 1, 1)
            love.graphics.printf(
                state.message,
                x + 20,
                y + height - 42,
                width - 40,
                "center"
            )
        end
    end

    host:registerService("shop", shop)
    host:registerWorldInspector("rpg.shop", function(world)
        local state = stateFor(world)
        local offers = {}
        local definition_value = definition(state.shop_id)
        for _, offer in ipairs(
            definition_value and definition_value.offers or {}
        ) do
            offers[#offers + 1] = {
                item_id = offer.item,
                name = localizedItemName(world, offer.item),
                buy_price = offer.buy_price,
                sell_price = offer.sell_price,
                owned = inventory:count(offer.item),
            }
        end
        return {
            shop = {
                active = state.active,
                shop_id = state.shop_id,
                mode = state.mode,
                selected = state.selected,
                message = state.message,
                balance = economy:balance(),
                offers = offers,
            },
        }
    end)
    host:registerSystem(input_system)
    host:registerSystem(draw_system)
end

return feature

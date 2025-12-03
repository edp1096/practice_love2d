-- engine/ui/screens/shop/state.lua
-- Shop state management and transaction logic

local shop_system = require "engine.systems.shop"
local locale = require "engine.core.locale"
local item_class = require "engine.entities.item"

local state = {}

-- Get current items list based on active tab
function state.getCurrentItems(shop_ui)
    if shop_ui.tab == "buy" then
        -- Return shop items with stock > 0
        local items = {}
        for _, item in ipairs(shop_ui.shop_data.items) do
            local stock = shop_system:getStock(shop_ui.shop_id, item.type)
            if stock > 0 then
                table.insert(items, {
                    type = item.type,
                    price = item.price,
                    stock = stock
                })
            end
        end
        return items
    else
        -- Return player inventory items
        local items = {}
        for item_id, item_data in pairs(shop_ui.inventory.items) do
            local sell_price = shop_system:getSellPrice(shop_ui.shop_id, item_data.item.type)
            table.insert(items, {
                item_id = item_id,
                type = item_data.item.type,
                quantity = item_data.item.quantity,
                sell_price = sell_price
            })
        end
        return items
    end
end

-- Get translated item name
function state.getItemName(shop_ui, item_type)
    local registry = shop_ui.item_registry or item_class.type_registry
    if registry and registry[item_type] then
        local item_def = registry[item_type]
        if item_def.name_key then
            local translated = locale:t(item_def.name_key)
            if translated ~= item_def.name_key then
                return translated
            end
        end
        return item_def.name or item_type
    end
    return item_type
end

-- Get translated item description
function state.getItemDescription(shop_ui, item_type)
    local registry = shop_ui.item_registry or item_class.type_registry
    if registry and registry[item_type] then
        local item_def = registry[item_type]
        if item_def.description_key then
            local translated = locale:t(item_def.description_key)
            if translated ~= item_def.description_key then
                return translated
            end
        end
        return item_def.description or ""
    end
    return ""
end

-- Get translated shop name
function state.getShopName(shop_ui)
    if shop_ui.shop_data then
        if shop_ui.shop_data.name_key then
            local translated = locale:t(shop_ui.shop_data.name_key)
            if translated ~= shop_ui.shop_data.name_key then
                return translated
            end
        end
        return shop_ui.shop_data.name or "Shop"
    end
    return "Shop"
end

-- Show message
function state.showMessage(shop_ui, msg)
    shop_ui.message = msg
    shop_ui.message_timer = shop_ui.message_duration
end

-- Switch tab
function state.switchTab(shop_ui, tab, play_sound)
    if shop_ui.tab ~= tab then
        shop_ui.tab = tab
        shop_ui.selected_index = 1
        shop_ui.scroll_offset = 0
        play_sound("ui", "select")
    end
end

-- Move selection
function state.moveSelection(shop_ui, direction, play_sound)
    local items = state.getCurrentItems(shop_ui)
    local count = #items

    if count == 0 then return end

    shop_ui.selected_index = shop_ui.selected_index + direction
    if shop_ui.selected_index < 1 then
        shop_ui.selected_index = count
    elseif shop_ui.selected_index > count then
        shop_ui.selected_index = 1
    end

    -- Adjust scroll
    if shop_ui.selected_index <= shop_ui.scroll_offset then
        shop_ui.scroll_offset = shop_ui.selected_index - 1
    elseif shop_ui.selected_index > shop_ui.scroll_offset + shop_ui.max_visible_items then
        shop_ui.scroll_offset = shop_ui.selected_index - shop_ui.max_visible_items
    end

    play_sound("ui", "select")
end

-- Confirm selection (enter quantity mode)
function state.confirmSelection(shop_ui, play_sound)
    local items = state.getCurrentItems(shop_ui)
    if #items == 0 or shop_ui.selected_index > #items then return end

    local item = items[shop_ui.selected_index]
    shop_ui.quantity_item = item
    shop_ui.quantity = 1

    -- Calculate max quantity
    if shop_ui.tab == "buy" then
        local price = item.price
        local affordable = math.floor(shop_ui.level_system:getGold() / price)
        shop_ui.quantity_max = math.min(item.stock, affordable)
    else
        shop_ui.quantity_max = item.quantity
    end

    if shop_ui.quantity_max <= 0 then
        state.showMessage(shop_ui, shop_ui.tab == "buy" and locale:t("shop.not_enough_gold") or locale:t("shop.no_items"))
        play_sound("ui", "error")
        return
    end

    shop_ui.quantity_mode = true
    play_sound("ui", "select")
end

-- Adjust quantity
function state.adjustQuantity(shop_ui, delta, play_sound)
    shop_ui.quantity = math.max(1, math.min(shop_ui.quantity_max, shop_ui.quantity + delta))
    play_sound("ui", "select")
end

-- Cancel quantity mode
function state.cancelQuantityMode(shop_ui, play_sound)
    shop_ui.quantity_mode = false
    shop_ui.quantity_item = nil
    play_sound("ui", "select")
end

-- Execute transaction
function state.executeTransaction(shop_ui, play_sound)
    if not shop_ui.quantity_item then return end

    local success, err
    if shop_ui.tab == "buy" then
        success, err = shop_system:buyItem(shop_ui.shop_id, shop_ui.quantity_item.type, shop_ui.quantity, shop_ui.level_system, shop_ui.inventory)
    else
        success, err = shop_system:sellItem(shop_ui.shop_id, shop_ui.quantity_item.type, shop_ui.quantity, shop_ui.level_system, shop_ui.inventory)
    end

    if success then
        local item_name = state.getItemName(shop_ui, shop_ui.quantity_item.type)
        local msg_key = shop_ui.tab == "buy" and "shop.purchased" or "shop.sold"
        state.showMessage(shop_ui, locale:t(msg_key, { count = shop_ui.quantity, item = item_name }))
        play_sound("ui", "purchase")
    else
        state.showMessage(shop_ui, err or "Transaction failed")
        play_sound("ui", "error")
    end

    -- Adjust selection if items were removed (sell mode)
    if shop_ui.tab == "sell" then
        local new_items = state.getCurrentItems(shop_ui)
        if shop_ui.selected_index > #new_items then
            shop_ui.selected_index = math.max(1, #new_items)
        end
    end

    shop_ui.quantity_mode = false
    shop_ui.quantity_item = nil
end

return state

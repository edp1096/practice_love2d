-- engine/ui/screens/shop/render.lua
-- Shop rendering

local display = require "engine.core.display"
local colors = require "engine.utils.colors"
local shapes = require "engine.utils.shapes"
local text_ui = require "engine.utils.text"
local locale = require "engine.core.locale"
local state = require "engine.ui.screens.shop.state"
local config = require "engine.ui.screens.shop.config"

-- Local references for performance
local PANEL_WIDTH = config.PANEL_WIDTH
local PANEL_HEIGHT = config.PANEL_HEIGHT
local DLG_WIDTH = config.DLG_WIDTH
local DLG_HEIGHT = config.DLG_HEIGHT
local TAB_WIDTH = config.TAB_WIDTH
local TAB_HEIGHT = config.TAB_HEIGHT
local TAB_GAP = config.TAB_GAP
local ITEM_HEIGHT = config.ITEM_HEIGHT
local LIST_PADDING = config.LIST_PADDING
local ARROW_WIDTH = config.ARROW_WIDTH
local ARROW_HEIGHT = config.ARROW_HEIGHT
local BTN_WIDTH = config.BTN_WIDTH
local BTN_HEIGHT = config.BTN_HEIGHT
local BTN_GAP = config.BTN_GAP

local render = {}

function render.draw(shop_ui)
    -- Note: display:Attach() is called by init.lua before this function
    local vw, vh = display:GetVirtualDimensions()

    -- Dim overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, vw, vh)

    -- Panel dimensions
    local panel_x = (vw - PANEL_WIDTH) / 2
    local panel_y = (vh - PANEL_HEIGHT) / 2

    -- Draw panel background
    love.graphics.setColor(colors.for_panel_bg or {0.15, 0.15, 0.2, 0.95})
    love.graphics.rectangle("fill", panel_x, panel_y, PANEL_WIDTH, PANEL_HEIGHT, 8, 8)

    -- Draw panel border
    love.graphics.setColor(colors.for_panel_border or {0.4, 0.4, 0.5, 1})
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, PANEL_WIDTH, PANEL_HEIGHT, 8, 8)

    -- Draw title (centered, top area)
    love.graphics.setFont(shop_ui.title_font)
    love.graphics.setColor(1, 1, 1, 1)
    local title = state.getShopName(shop_ui)
    local title_width = shop_ui.title_font:getWidth(title)
    love.graphics.print(title, panel_x + (PANEL_WIDTH - title_width) / 2, panel_y + 10)

    -- Draw tabs
    render.drawTabs(shop_ui, panel_x, panel_y)

    -- Draw items list
    render.drawItemsList(shop_ui, panel_x, panel_y)

    -- Draw quantity selection overlay
    if shop_ui.quantity_mode and shop_ui.quantity_item then
        render.drawQuantityDialog(shop_ui, panel_x, panel_y)
    end

    -- Draw toast message
    if shop_ui.message and not shop_ui.quantity_mode then
        render.drawMessage(shop_ui, panel_x, panel_y)
    end

    -- Draw close button (only when not in quantity mode)
    if not shop_ui.quantity_mode then
        local close_x = panel_x + PANEL_WIDTH - shop_ui.close_button_size - shop_ui.close_button_padding
        local close_y = panel_y + shop_ui.close_button_padding
        shapes:drawCloseButton(close_x, close_y, shop_ui.close_button_size, shop_ui.close_button_hovered)
    end

    -- Draw controls hint
    render.drawHints(shop_ui, panel_x, panel_y)
    -- Note: display:Detach() is called by init.lua after this function
end

function render.drawTabs(shop_ui, panel_x, panel_y)
    local tab_y = panel_y + 50
    local buy_x = panel_x + LIST_PADDING

    -- Buy tab
    if shop_ui.tab == "buy" then
        love.graphics.setColor(0.3, 0.5, 0.3, 1)
    elseif shop_ui.hovered_tab_buy then
        love.graphics.setColor(0.28, 0.38, 0.28, 1)
    else
        love.graphics.setColor(0.2, 0.2, 0.25, 1)
    end
    love.graphics.rectangle("fill", buy_x, tab_y, TAB_WIDTH, TAB_HEIGHT, 4, 4)
    if shop_ui.hovered_tab_buy and shop_ui.tab ~= "buy" then
        love.graphics.setColor(0.4, 0.6, 0.4, 0.8)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", buy_x, tab_y, TAB_WIDTH, TAB_HEIGHT, 4, 4)
    end
    local buy_text = locale:t("shop.buy")
    love.graphics.setColor(1, 1, 1, shop_ui.tab == "buy" and 1 or (shop_ui.hovered_tab_buy and 0.9 or 0.6))
    love.graphics.setFont(shop_ui.item_font)
    text_ui:draw(buy_text, buy_x + TAB_WIDTH/2 - shop_ui.item_font:getWidth(buy_text)/2, tab_y + 4, nil, shop_ui.item_font)

    -- Sell tab
    local sell_x = buy_x + TAB_WIDTH + TAB_GAP
    if shop_ui.tab == "sell" then
        love.graphics.setColor(0.5, 0.3, 0.3, 1)
    elseif shop_ui.hovered_tab_sell then
        love.graphics.setColor(0.38, 0.28, 0.28, 1)
    else
        love.graphics.setColor(0.2, 0.2, 0.25, 1)
    end
    love.graphics.rectangle("fill", sell_x, tab_y, TAB_WIDTH, TAB_HEIGHT, 4, 4)
    if shop_ui.hovered_tab_sell and shop_ui.tab ~= "sell" then
        love.graphics.setColor(0.6, 0.4, 0.4, 0.8)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", sell_x, tab_y, TAB_WIDTH, TAB_HEIGHT, 4, 4)
    end
    local sell_text = locale:t("shop.sell")
    love.graphics.setColor(1, 1, 1, shop_ui.tab == "sell" and 1 or (shop_ui.hovered_tab_sell and 0.9 or 0.6))
    text_ui:draw(sell_text, sell_x + TAB_WIDTH/2 - shop_ui.item_font:getWidth(sell_text)/2, tab_y + 4, nil, shop_ui.item_font)

    -- Draw gold
    love.graphics.setFont(shop_ui.item_font)
    love.graphics.setColor(1, 0.85, 0, 1)
    local gold_text = locale:t("shop.gold") .. ": " .. shop_ui.level_system:getGold()
    love.graphics.print(gold_text, panel_x + PANEL_WIDTH - shop_ui.item_font:getWidth(gold_text) - LIST_PADDING, tab_y + 4)
end

function render.drawItemsList(shop_ui, panel_x, panel_y)
    local tab_y = panel_y + 50
    local list_y = tab_y + 35
    local list_height = 160

    local items = state.getCurrentItems(shop_ui)

    if #items == 0 then
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        local empty_text = shop_ui.tab == "buy" and locale:t("shop.nothing_in_stock") or locale:t("shop.no_items_to_sell")
        love.graphics.print(empty_text, panel_x + 20, list_y + 20)
    else
        for i = 1, math.min(shop_ui.max_visible_items, #items - shop_ui.scroll_offset) do
            local idx = i + shop_ui.scroll_offset
            local item = items[idx]
            local item_y = list_y + (i - 1) * ITEM_HEIGHT

            -- Hover highlight
            if idx == shop_ui.hovered_item_index and idx ~= shop_ui.selected_index then
                love.graphics.setColor(0.25, 0.3, 0.35, 0.6)
                love.graphics.rectangle("fill", panel_x + LIST_PADDING, item_y + 2, PANEL_WIDTH - LIST_PADDING * 2, ITEM_HEIGHT - 4, 3, 3)
            end

            -- Selection highlight
            if idx == shop_ui.selected_index then
                love.graphics.setColor(0.3, 0.4, 0.5, 0.8)
                love.graphics.rectangle("fill", panel_x + LIST_PADDING, item_y + 2, PANEL_WIDTH - LIST_PADDING * 2, ITEM_HEIGHT - 4, 3, 3)
            end

            local text_y = item_y + 5

            -- Item name
            love.graphics.setColor(1, 1, 1, 1)
            local name = state.getItemName(shop_ui, item.type)
            love.graphics.print(name, panel_x + 20, text_y)

            -- Price/quantity
            if shop_ui.tab == "buy" then
                love.graphics.setColor(1, 0.85, 0, 1)
                love.graphics.print(item.price .. "G", panel_x + PANEL_WIDTH - 85, text_y)
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
                love.graphics.print("x" .. item.stock, panel_x + PANEL_WIDTH - 40, text_y)
            else
                love.graphics.setColor(0.5, 0.8, 0.5, 1)
                love.graphics.print("+" .. item.sell_price .. "G", panel_x + PANEL_WIDTH - 85, text_y)
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
                love.graphics.print("x" .. item.quantity, panel_x + PANEL_WIDTH - 40, text_y)
            end
        end

        -- Scroll indicators
        if shop_ui.scroll_offset > 0 then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.print("^", panel_x + PANEL_WIDTH/2 - 3, list_y - 12)
        end
        if shop_ui.scroll_offset + shop_ui.max_visible_items < #items then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.print("v", panel_x + PANEL_WIDTH/2 - 3, list_y + list_height - 5)
        end
    end
end

function render.drawQuantityDialog(shop_ui, panel_x, panel_y)
    -- Dim background
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", panel_x, panel_y, PANEL_WIDTH, PANEL_HEIGHT, 8, 8)

    local dlg_x = panel_x + (PANEL_WIDTH - DLG_WIDTH) / 2
    local dlg_y = panel_y + (PANEL_HEIGHT - DLG_HEIGHT) / 2

    -- Dialog background
    love.graphics.setColor(0.2, 0.2, 0.25, 1)
    love.graphics.rectangle("fill", dlg_x, dlg_y, DLG_WIDTH, DLG_HEIGHT, 6, 6)
    love.graphics.setColor(0.5, 0.5, 0.6, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", dlg_x, dlg_y, DLG_WIDTH, DLG_HEIGHT, 6, 6)

    -- Item name
    love.graphics.setColor(1, 1, 1, 1)
    local item_name = state.getItemName(shop_ui, shop_ui.quantity_item.type)
    local name_width = shop_ui.item_font:getWidth(item_name)
    love.graphics.print(item_name, dlg_x + (DLG_WIDTH - name_width) / 2, dlg_y + 12)

    -- Quantity selector
    local qty_y = dlg_y + 45

    -- Left arrow
    if shop_ui.hovered_qty_left then
        love.graphics.setColor(0.4, 0.5, 0.6, 0.8)
        love.graphics.rectangle("fill", dlg_x + 30, qty_y - 2, ARROW_WIDTH, ARROW_HEIGHT, 3, 3)
    end
    love.graphics.setColor(shop_ui.hovered_qty_left and 1 or 0.7, shop_ui.hovered_qty_left and 1 or 0.7, shop_ui.hovered_qty_left and 1 or 0.7, 1)
    love.graphics.print("<", dlg_x + 40, qty_y)

    -- Right arrow
    if shop_ui.hovered_qty_right then
        love.graphics.setColor(0.4, 0.5, 0.6, 0.8)
        love.graphics.rectangle("fill", dlg_x + DLG_WIDTH - 60, qty_y - 2, ARROW_WIDTH, ARROW_HEIGHT, 3, 3)
    end
    love.graphics.setColor(shop_ui.hovered_qty_right and 1 or 0.7, shop_ui.hovered_qty_right and 1 or 0.7, shop_ui.hovered_qty_right and 1 or 0.7, 1)
    love.graphics.print(">", dlg_x + DLG_WIDTH - 50, qty_y)

    -- Quantity
    love.graphics.setColor(1, 1, 1, 1)
    local qty_text = tostring(shop_ui.quantity)
    local qty_width = shop_ui.item_font:getWidth(qty_text)
    love.graphics.print(qty_text, dlg_x + (DLG_WIDTH - qty_width) / 2, qty_y)

    -- Total price
    local total_price, price_text
    if shop_ui.tab == "buy" then
        total_price = shop_ui.quantity_item.price * shop_ui.quantity
        price_text = locale:t("shop.total") .. ": " .. total_price .. "G"
        love.graphics.setColor(1, 0.85, 0, 1)
    else
        total_price = (shop_ui.quantity_item.sell_price or 0) * shop_ui.quantity
        price_text = locale:t("shop.get") .. ": +" .. total_price .. "G"
        love.graphics.setColor(0.5, 0.8, 0.5, 1)
    end
    local price_width = shop_ui.item_font:getWidth(price_text)
    love.graphics.print(price_text, dlg_x + (DLG_WIDTH - price_width) / 2, dlg_y + 70)

    -- Action buttons
    local btn_y = dlg_y + 90
    local btns_total_width = BTN_WIDTH * 2 + BTN_GAP
    local ok_x = dlg_x + (DLG_WIDTH - btns_total_width) / 2
    local cancel_x = ok_x + BTN_WIDTH + BTN_GAP

    -- OK button
    if shop_ui.hovered_qty_ok then
        love.graphics.setColor(0.3, 0.5, 0.3, 0.9)
    else
        love.graphics.setColor(0.25, 0.35, 0.25, 0.7)
    end
    love.graphics.rectangle("fill", ok_x, btn_y, BTN_WIDTH, BTN_HEIGHT, 3, 3)
    love.graphics.setColor(shop_ui.hovered_qty_ok and 1 or 0.8, 1, shop_ui.hovered_qty_ok and 1 or 0.8, 1)
    local ok_text = locale:t("shop.ok")
    love.graphics.print(ok_text, ok_x + (BTN_WIDTH - shop_ui.item_font:getWidth(ok_text)) / 2, btn_y + 4)

    -- Cancel button
    if shop_ui.hovered_qty_cancel then
        love.graphics.setColor(0.5, 0.3, 0.3, 0.9)
    else
        love.graphics.setColor(0.35, 0.25, 0.25, 0.7)
    end
    love.graphics.rectangle("fill", cancel_x, btn_y, BTN_WIDTH, BTN_HEIGHT, 3, 3)
    love.graphics.setColor(1, shop_ui.hovered_qty_cancel and 1 or 0.8, shop_ui.hovered_qty_cancel and 1 or 0.8, 1)
    local cancel_text = locale:t("shop.cancel")
    love.graphics.print(cancel_text, cancel_x + (BTN_WIDTH - shop_ui.item_font:getWidth(cancel_text)) / 2, btn_y + 4)
end

function render.drawMessage(shop_ui, panel_x, panel_y)
    local msg_width = shop_ui.item_font:getWidth(shop_ui.message) + 24
    local msg_height = 24
    local msg_x = panel_x + (PANEL_WIDTH - msg_width) / 2
    local msg_y = panel_y + PANEL_HEIGHT - 50

    love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", msg_x, msg_y, msg_width, msg_height, 4, 4)
    love.graphics.setColor(0.4, 0.4, 0.5, 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", msg_x, msg_y, msg_width, msg_height, 4, 4)
    love.graphics.setColor(1, 1, 0.5, 1)
    love.graphics.print(shop_ui.message, msg_x + 12, msg_y + 5)
end

function render.drawHints(shop_ui, panel_x, panel_y)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.setFont(shop_ui.item_font)
    local hint_y = panel_y + PANEL_HEIGHT - 25

    if shop_ui.quantity_mode then
        local hint_qty = "[<>] " .. locale:t("shop.hint_qty") .. "  [^v] " .. locale:t("shop.hint_qty_10") .. "  [A] " .. locale:t("shop.ok") .. "  [B] " .. locale:t("shop.cancel")
        love.graphics.print(hint_qty, panel_x + 15, hint_y)
    else
        local hint_normal = "[A] " .. locale:t("shop.hint_select") .. "  [B] " .. locale:t("shop.hint_close") .. "  [LB/RB] " .. locale:t("shop.hint_tab")
        love.graphics.print(hint_normal, panel_x + 20, hint_y)
    end
end

return render

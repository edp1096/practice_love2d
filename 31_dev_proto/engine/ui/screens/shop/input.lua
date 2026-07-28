-- engine/ui/screens/shop/input.lua
-- Shop input handling

local display = require "engine.core.display"
local coords = require "engine.core.coords"
local input = require "engine.core.input"
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

local shop_input = {}

-- Handle gamepad input
function shop_input.handleGamepadInput(shop_ui, dt, play_sound)
    -- Quantity mode input
    if shop_ui.quantity_mode then
        if input:wasPressed("left") then
            state.adjustQuantity(shop_ui, -1, play_sound)
        elseif input:wasPressed("right") then
            state.adjustQuantity(shop_ui, 1, play_sound)
        elseif input:wasPressed("up") then
            state.adjustQuantity(shop_ui, 10, play_sound)
        elseif input:wasPressed("down") then
            state.adjustQuantity(shop_ui, -10, play_sound)
        elseif input:wasPressed("confirm") or input:wasPressed("attack") then
            state.executeTransaction(shop_ui, play_sound)
        elseif input:wasPressed("cancel") or input:wasPressed("pause") then
            state.cancelQuantityMode(shop_ui, play_sound)
        end
        return
    end

    -- Tab switching with LB/RB
    if input:wasPressed("prev_tab") then
        state.switchTab(shop_ui, "buy", play_sound)
    elseif input:wasPressed("next_tab") then
        state.switchTab(shop_ui, "sell", play_sound)
    end

    -- Navigation with D-pad or joystick
    local move_y = 0
    if input:wasPressed("up") then
        move_y = -1
    elseif input:wasPressed("down") then
        move_y = 1
    end

    if move_y ~= 0 then
        state.moveSelection(shop_ui, move_y, play_sound)
    end

    -- Confirm with A
    if input:wasPressed("confirm") or input:wasPressed("attack") then
        state.confirmSelection(shop_ui, play_sound)
    end

    -- Close with B or Back
    if input:wasPressed("cancel") or input:wasPressed("pause") then
        shop_ui:close()
    end
end

-- Mouse moved handler
function shop_input.mousemoved(shop_ui, x, y)
    local vx, vy = coords:physicalToVirtual(x, y)
    local vw, vh = display:GetVirtualDimensions()

    local panel_x = (vw - PANEL_WIDTH) / 2
    local panel_y = (vh - PANEL_HEIGHT) / 2

    -- Check close button hover
    local close_x = panel_x + PANEL_WIDTH - shop_ui.close_button_size - shop_ui.close_button_padding
    local close_y = panel_y + shop_ui.close_button_padding
    shop_ui.close_button_hovered = vx >= close_x and vx <= close_x + shop_ui.close_button_size
        and vy >= close_y and vy <= close_y + shop_ui.close_button_size

    -- Quantity mode hover detection
    if shop_ui.quantity_mode then
        local dlg_x = panel_x + (PANEL_WIDTH - DLG_WIDTH) / 2
        local dlg_y = panel_y + (PANEL_HEIGHT - DLG_HEIGHT) / 2
        local qty_y = dlg_y + 45

        -- Left arrow hover
        shop_ui.hovered_qty_left = vx >= dlg_x + 30 and vx <= dlg_x + 30 + ARROW_WIDTH
            and vy >= qty_y - 2 and vy <= qty_y - 2 + ARROW_HEIGHT

        -- Right arrow hover
        shop_ui.hovered_qty_right = vx >= dlg_x + DLG_WIDTH - 60 and vx <= dlg_x + DLG_WIDTH - 60 + ARROW_WIDTH
            and vy >= qty_y - 2 and vy <= qty_y - 2 + ARROW_HEIGHT

        -- OK/Cancel button hover
        local btn_y = dlg_y + 90
        local btns_total_width = BTN_WIDTH * 2 + BTN_GAP
        local ok_x = dlg_x + (DLG_WIDTH - btns_total_width) / 2
        local cancel_x = ok_x + BTN_WIDTH + BTN_GAP

        shop_ui.hovered_qty_ok = vx >= ok_x and vx <= ok_x + BTN_WIDTH
            and vy >= btn_y and vy <= btn_y + BTN_HEIGHT
        shop_ui.hovered_qty_cancel = vx >= cancel_x and vx <= cancel_x + BTN_WIDTH
            and vy >= btn_y and vy <= btn_y + BTN_HEIGHT

        -- Clear item hover in quantity mode
        shop_ui.hovered_item_index = nil
    else
        -- Clear quantity hover states
        shop_ui.hovered_qty_left = false
        shop_ui.hovered_qty_right = false
        shop_ui.hovered_qty_ok = false
        shop_ui.hovered_qty_cancel = false

        -- Tab hover detection
        local tab_y = panel_y + 50
        local buy_x = panel_x + LIST_PADDING
        local sell_x = buy_x + TAB_WIDTH + TAB_GAP

        shop_ui.hovered_tab_buy = vx >= buy_x and vx <= buy_x + TAB_WIDTH
            and vy >= tab_y and vy <= tab_y + TAB_HEIGHT
        shop_ui.hovered_tab_sell = vx >= sell_x and vx <= sell_x + TAB_WIDTH
            and vy >= tab_y and vy <= tab_y + TAB_HEIGHT

        -- Item list hover detection
        local list_y = tab_y + 35
        local items = state.getCurrentItems(shop_ui)

        shop_ui.hovered_item_index = nil
        for i = 1, math.min(shop_ui.max_visible_items, #items - shop_ui.scroll_offset) do
            local idx = i + shop_ui.scroll_offset
            local item_y = list_y + (i - 1) * ITEM_HEIGHT

            if vx >= panel_x + LIST_PADDING and vx <= panel_x + PANEL_WIDTH - LIST_PADDING
                and vy >= item_y and vy <= item_y + ITEM_HEIGHT then
                shop_ui.hovered_item_index = idx
                break
            end
        end
    end
end

-- Mouse pressed handler
function shop_input.mousepressed(shop_ui, x, y, button, play_sound)
    if button ~= 1 then return end

    local vx, vy = coords:physicalToVirtual(x, y)
    local vw, vh = display:GetVirtualDimensions()

    local panel_x = (vw - PANEL_WIDTH) / 2
    local panel_y = (vh - PANEL_HEIGHT) / 2

    -- Quantity mode mouse handling
    if shop_ui.quantity_mode then
        if shop_ui.hovered_qty_left then
            state.adjustQuantity(shop_ui, -1, play_sound)
            return
        end
        if shop_ui.hovered_qty_right then
            state.adjustQuantity(shop_ui, 1, play_sound)
            return
        end
        if shop_ui.hovered_qty_ok then
            state.executeTransaction(shop_ui, play_sound)
            return
        end
        if shop_ui.hovered_qty_cancel then
            state.cancelQuantityMode(shop_ui, play_sound)
            return
        end
        -- Cancel - click outside dialog
        local dlg_x = panel_x + (PANEL_WIDTH - DLG_WIDTH) / 2
        local dlg_y = panel_y + (PANEL_HEIGHT - DLG_HEIGHT) / 2
        if vx < dlg_x or vx > dlg_x + DLG_WIDTH or vy < dlg_y or vy > dlg_y + DLG_HEIGHT then
            state.cancelQuantityMode(shop_ui, play_sound)
            return
        end
        return
    end

    -- Close button
    if shop_ui.close_button_hovered then
        shop_ui:close()
        return
    end

    -- Tab click using hover state
    if shop_ui.hovered_tab_buy then
        state.switchTab(shop_ui, "buy", play_sound)
        return
    end
    if shop_ui.hovered_tab_sell then
        state.switchTab(shop_ui, "sell", play_sound)
        return
    end

    -- Item clicks
    local tab_y = panel_y + 50
    local list_y = tab_y + 35
    local items = state.getCurrentItems(shop_ui)

    for i = 1, math.min(shop_ui.max_visible_items, #items - shop_ui.scroll_offset) do
        local idx = i + shop_ui.scroll_offset
        local item_y = list_y + (i - 1) * ITEM_HEIGHT

        if vx >= panel_x + LIST_PADDING and vx <= panel_x + PANEL_WIDTH - LIST_PADDING
            and vy >= item_y and vy <= item_y + ITEM_HEIGHT then
            shop_ui.selected_index = idx
            state.confirmSelection(shop_ui, play_sound)
            return
        end
    end
end

-- Wheel moved handler
function shop_input.wheelmoved(shop_ui, x, y, play_sound)
    if shop_ui.quantity_mode then
        if y > 0 then
            state.adjustQuantity(shop_ui, 1, play_sound)
        elseif y < 0 then
            state.adjustQuantity(shop_ui, -1, play_sound)
        end
    else
        if y > 0 then
            state.moveSelection(shop_ui, -1, play_sound)
        elseif y < 0 then
            state.moveSelection(shop_ui, 1, play_sound)
        end
    end
end

-- Key pressed handler
function shop_input.keypressed(shop_ui, key, play_sound)
    if shop_ui.quantity_mode then
        if key == "escape" then
            state.cancelQuantityMode(shop_ui, play_sound)
        elseif key == "left" then
            state.adjustQuantity(shop_ui, -1, play_sound)
        elseif key == "right" then
            state.adjustQuantity(shop_ui, 1, play_sound)
        elseif key == "up" then
            state.adjustQuantity(shop_ui, 10, play_sound)
        elseif key == "down" then
            state.adjustQuantity(shop_ui, -10, play_sound)
        elseif key == "return" or key == "space" then
            state.executeTransaction(shop_ui, play_sound)
        end
        return
    end

    if key == "escape" then
        shop_ui:close()
    elseif key == "up" then
        state.moveSelection(shop_ui, -1, play_sound)
    elseif key == "down" then
        state.moveSelection(shop_ui, 1, play_sound)
    elseif key == "return" or key == "space" then
        state.confirmSelection(shop_ui, play_sound)
    elseif key == "tab" then
        state.switchTab(shop_ui, shop_ui.tab == "buy" and "sell" or "buy", play_sound)
    end
end

-- Gamepad pressed handler
function shop_input.gamepadpressed(shop_ui, joystick, button, play_sound)
    if shop_ui.quantity_mode then
        if button == "dpleft" then
            state.adjustQuantity(shop_ui, -1, play_sound)
        elseif button == "dpright" then
            state.adjustQuantity(shop_ui, 1, play_sound)
        elseif button == "dpup" then
            state.adjustQuantity(shop_ui, 10, play_sound)
        elseif button == "dpdown" then
            state.adjustQuantity(shop_ui, -10, play_sound)
        elseif button == "a" then
            state.executeTransaction(shop_ui, play_sound)
        elseif button == "b" then
            state.cancelQuantityMode(shop_ui, play_sound)
        end
        return
    end

    if button == "dpup" then
        state.moveSelection(shop_ui, -1, play_sound)
    elseif button == "dpdown" then
        state.moveSelection(shop_ui, 1, play_sound)
    elseif button == "a" then
        state.confirmSelection(shop_ui, play_sound)
    elseif button == "b" or button == "start" then
        shop_ui:close()
    elseif button == "leftshoulder" then
        state.switchTab(shop_ui, "buy", play_sound)
    elseif button == "rightshoulder" then
        state.switchTab(shop_ui, "sell", play_sound)
    end
end

-- Touch handlers
function shop_input.touchpressed(shop_ui, id, x, y, dx, dy, pressure, play_sound)
    shop_input.mousemoved(shop_ui, x, y)
    shop_input.mousepressed(shop_ui, x, y, 1, play_sound)
end

function shop_input.touchmoved(shop_ui, id, x, y, dx, dy, pressure)
    shop_input.mousemoved(shop_ui, x, y)
end

function shop_input.touchreleased(shop_ui, id, x, y, dx, dy, pressure)
    shop_ui.hovered_item_index = nil
    shop_ui.hovered_qty_left = false
    shop_ui.hovered_qty_right = false
    shop_ui.hovered_qty_ok = false
    shop_ui.hovered_qty_cancel = false
    shop_ui.hovered_tab_buy = false
    shop_ui.hovered_tab_sell = false
    shop_ui.close_button_hovered = false
end

return shop_input

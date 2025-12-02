-- engine/ui/screens/shop/init.lua
-- Shop UI overlay

local shop_ui = {}

local display = require "engine.core.display"
local sound = require "engine.core.sound"
local fonts = require "engine.utils.fonts"
local shapes = require "engine.utils.shapes"
local text_ui = require "engine.utils.text"
local input = require "engine.core.input"
local colors = require "engine.utils.colors"
local ui_constants = require "engine.ui.constants"
local coords = require "engine.core.coords"
local shop_system = require "engine.systems.shop"

-- Safe sound wrapper
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

function shop_ui:enter(previous, shop_id, inventory, level_system, item_registry)
    self.previous_scene = previous
    self.shop_id = shop_id
    self.inventory = inventory
    self.level_system = level_system
    self.item_registry = item_registry

    -- Get shop data
    self.shop_data = shop_system:getShop(shop_id)
    if not self.shop_data then
        print("[Shop] ERROR: Shop not found:", shop_id)
        return
    end

    -- Hide virtual gamepad
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    -- UI State
    self.tab = "buy"  -- "buy" or "sell"
    self.selected_index = 1
    self.scroll_offset = 0
    self.max_visible_items = 6

    -- Message display
    self.message = nil
    self.message_timer = 0
    self.message_duration = 2.0

    -- Fonts
    self.title_font = love.graphics.newFont(ui_constants.FONT_SIZE_TITLE)
    self.item_font = fonts.info or love.graphics.getFont()

    -- Close button
    self.close_button_size = ui_constants.CLOSE_BUTTON_SIZE
    self.close_button_padding = ui_constants.CLOSE_BUTTON_PADDING
    self.close_button_hovered = false

    -- Joystick cooldown
    self.joystick_cooldown = 0
    self.joystick_repeat_delay = 0.15

    -- Quantity selection mode
    self.quantity_mode = false
    self.quantity = 1
    self.quantity_max = 1
    self.quantity_item = nil

    play_sound("ui", "open")
end

function shop_ui:leave()
    if input.virtual_gamepad then
        input.virtual_gamepad:show()
    end
end

function shop_ui:update(dt)
    -- Update message timer
    if self.message_timer > 0 then
        self.message_timer = self.message_timer - dt
        if self.message_timer <= 0 then
            self.message = nil
        end
    end

    -- Update joystick cooldown
    if self.joystick_cooldown > 0 then
        self.joystick_cooldown = self.joystick_cooldown - dt
    end

    -- Handle gamepad input
    self:handleGamepadInput(dt)
end

function shop_ui:handleGamepadInput(dt)
    -- Quantity mode input
    if self.quantity_mode then
        if input:wasPressed("left") then
            self:adjustQuantity(-1)
        elseif input:wasPressed("right") then
            self:adjustQuantity(1)
        elseif input:wasPressed("up") then
            self:adjustQuantity(10)
        elseif input:wasPressed("down") then
            self:adjustQuantity(-10)
        elseif input:wasPressed("confirm") or input:wasPressed("attack") then
            self:executeTransaction()
        elseif input:wasPressed("cancel") or input:wasPressed("pause") then
            self:cancelQuantityMode()
        end
        return
    end

    -- Tab switching with LB/RB
    if input:wasPressed("prev_tab") then
        self:switchTab("buy")
    elseif input:wasPressed("next_tab") then
        self:switchTab("sell")
    end

    -- Navigation with D-pad or joystick
    local move_y = 0
    if input:wasPressed("up") then
        move_y = -1
    elseif input:wasPressed("down") then
        move_y = 1
    end

    if move_y ~= 0 then
        self:moveSelection(move_y)
    end

    -- Confirm with A
    if input:wasPressed("confirm") or input:wasPressed("attack") then
        self:confirmSelection()
    end

    -- Close with B or Back
    if input:wasPressed("cancel") or input:wasPressed("pause") then
        self:close()
    end
end

function shop_ui:switchTab(tab)
    if self.tab ~= tab then
        self.tab = tab
        self.selected_index = 1
        self.scroll_offset = 0
        play_sound("ui", "select")
    end
end

function shop_ui:moveSelection(direction)
    local items = self:getCurrentItems()
    local count = #items

    if count == 0 then return end

    self.selected_index = self.selected_index + direction
    if self.selected_index < 1 then
        self.selected_index = count
    elseif self.selected_index > count then
        self.selected_index = 1
    end

    -- Adjust scroll
    if self.selected_index <= self.scroll_offset then
        self.scroll_offset = self.selected_index - 1
    elseif self.selected_index > self.scroll_offset + self.max_visible_items then
        self.scroll_offset = self.selected_index - self.max_visible_items
    end

    play_sound("ui", "select")
end

function shop_ui:confirmSelection()
    local items = self:getCurrentItems()
    if #items == 0 or self.selected_index > #items then return end

    local item = items[self.selected_index]
    self.quantity_item = item
    self.quantity = 1

    -- Calculate max quantity
    if self.tab == "buy" then
        local price = item.price
        local affordable = math.floor(self.level_system:getGold() / price)
        self.quantity_max = math.min(item.stock, affordable)
    else
        self.quantity_max = item.quantity
    end

    if self.quantity_max <= 0 then
        self:showMessage(self.tab == "buy" and "Not enough gold" or "No items")
        play_sound("ui", "error")
        return
    end

    self.quantity_mode = true
    play_sound("ui", "select")
end

function shop_ui:adjustQuantity(delta)
    self.quantity = math.max(1, math.min(self.quantity_max, self.quantity + delta))
    play_sound("ui", "select")
end

function shop_ui:cancelQuantityMode()
    self.quantity_mode = false
    self.quantity_item = nil
    play_sound("ui", "select")
end

function shop_ui:executeTransaction()
    if not self.quantity_item then return end

    local success_count = 0
    local last_error = nil

    for i = 1, self.quantity do
        local success, err
        if self.tab == "buy" then
            success, err = shop_system:buyItem(self.shop_id, self.quantity_item.type, self.level_system, self.inventory)
        else
            success, err = shop_system:sellItem(self.shop_id, self.quantity_item.item_id, self.level_system, self.inventory)
        end

        if success then
            success_count = success_count + 1
        else
            last_error = err
            break
        end
    end

    if success_count > 0 then
        local action = self.tab == "buy" and "Purchased" or "Sold"
        self:showMessage(action .. " " .. success_count .. "x " .. self:getItemName(self.quantity_item.type))
        play_sound("ui", "purchase")
    else
        self:showMessage(last_error or "Transaction failed")
        play_sound("ui", "error")
    end

    -- Adjust selection if items were removed (sell mode)
    if self.tab == "sell" then
        local new_items = self:getCurrentItems()
        if self.selected_index > #new_items then
            self.selected_index = math.max(1, #new_items)
        end
    end

    self.quantity_mode = false
    self.quantity_item = nil
end

function shop_ui:getCurrentItems()
    if self.tab == "buy" then
        -- Return shop items with stock > 0
        local items = {}
        for _, item in ipairs(self.shop_data.items) do
            local stock = shop_system:getStock(self.shop_id, item.type)
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
        for item_id, item_data in pairs(self.inventory.items) do
            local sell_price = shop_system:getSellPrice(self.shop_id, item_data.item.type)
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

function shop_ui:getItemName(item_type)
    if self.item_registry and self.item_registry[item_type] then
        return self.item_registry[item_type].name or item_type
    end
    return item_type
end

function shop_ui:showMessage(msg)
    self.message = msg
    self.message_timer = self.message_duration
end

function shop_ui:close()
    play_sound("ui", "close")
    local scene_control = require "engine.core.scene_control"
    scene_control.pop()
end

function shop_ui:draw()
    display:Attach()

    -- Draw previous scene dimmed
    if self.previous_scene and self.previous_scene.draw then
        self.previous_scene:draw()
    end

    local vw, vh = display:GetVirtualDimensions()

    -- Dim overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, vw, vh)

    -- Panel dimensions
    local panel_width = 300
    local panel_height = 280
    local panel_x = (vw - panel_width) / 2
    local panel_y = (vh - panel_height) / 2

    -- Draw panel background
    love.graphics.setColor(colors.for_panel_bg or {0.15, 0.15, 0.2, 0.95})
    love.graphics.rectangle("fill", panel_x, panel_y, panel_width, panel_height, 8, 8)

    -- Draw panel border
    love.graphics.setColor(colors.for_panel_border or {0.4, 0.4, 0.5, 1})
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, panel_width, panel_height, 8, 8)

    -- Draw title
    love.graphics.setFont(self.title_font)
    love.graphics.setColor(1, 1, 1, 1)
    local title = self.shop_data.name or "Shop"
    local title_width = self.title_font:getWidth(title)
    love.graphics.print(title, panel_x + (panel_width - title_width) / 2, panel_y + 10)

    -- Draw gold
    love.graphics.setFont(self.item_font)
    love.graphics.setColor(1, 0.85, 0, 1)
    local gold_text = "Gold: " .. self.level_system:getGold()
    love.graphics.print(gold_text, panel_x + panel_width - self.item_font:getWidth(gold_text) - 15, panel_y + 12)

    -- Draw tabs
    local tab_y = panel_y + 40
    local tab_width = 80
    local tab_height = 25

    -- Buy tab
    local buy_x = panel_x + 30
    if self.tab == "buy" then
        love.graphics.setColor(0.3, 0.5, 0.3, 1)
    else
        love.graphics.setColor(0.2, 0.2, 0.25, 1)
    end
    love.graphics.rectangle("fill", buy_x, tab_y, tab_width, tab_height, 4, 4)
    love.graphics.setColor(1, 1, 1, self.tab == "buy" and 1 or 0.6)
    text_ui:draw("Buy", buy_x + tab_width/2 - self.item_font:getWidth("Buy")/2, tab_y + 5)

    -- Sell tab
    local sell_x = panel_x + panel_width - tab_width - 30
    if self.tab == "sell" then
        love.graphics.setColor(0.5, 0.3, 0.3, 1)
    else
        love.graphics.setColor(0.2, 0.2, 0.25, 1)
    end
    love.graphics.rectangle("fill", sell_x, tab_y, tab_width, tab_height, 4, 4)
    love.graphics.setColor(1, 1, 1, self.tab == "sell" and 1 or 0.6)
    text_ui:draw("Sell", sell_x + tab_width/2 - self.item_font:getWidth("Sell")/2, tab_y + 5)

    -- Draw items list
    local list_y = tab_y + 35
    local list_height = 150
    local item_height = 24

    local items = self:getCurrentItems()

    if #items == 0 then
        love.graphics.setColor(0.6, 0.6, 0.6, 1)
        local empty_text = self.tab == "buy" and "Nothing in stock" or "No items to sell"
        love.graphics.print(empty_text, panel_x + 20, list_y + 20)
    else
        for i = 1, math.min(self.max_visible_items, #items - self.scroll_offset) do
            local idx = i + self.scroll_offset
            local item = items[idx]
            local item_y = list_y + (i - 1) * item_height

            -- Selection highlight
            if idx == self.selected_index then
                love.graphics.setColor(0.3, 0.4, 0.5, 0.8)
                love.graphics.rectangle("fill", panel_x + 15, item_y, panel_width - 30, item_height - 2, 3, 3)
            end

            -- Item name
            love.graphics.setColor(1, 1, 1, 1)
            local name = self:getItemName(item.type)
            love.graphics.print(name, panel_x + 20, item_y + 3)

            -- Price/quantity
            if self.tab == "buy" then
                -- Show price and stock
                love.graphics.setColor(1, 0.85, 0, 1)
                local price_text = item.price .. "G"
                love.graphics.print(price_text, panel_x + panel_width - 80, item_y + 3)

                love.graphics.setColor(0.7, 0.7, 0.7, 1)
                local stock_text = "x" .. item.stock
                love.graphics.print(stock_text, panel_x + panel_width - 35, item_y + 3)
            else
                -- Show sell price and quantity
                love.graphics.setColor(0.5, 0.8, 0.5, 1)
                local sell_text = "+" .. item.sell_price .. "G"
                love.graphics.print(sell_text, panel_x + panel_width - 80, item_y + 3)

                love.graphics.setColor(0.7, 0.7, 0.7, 1)
                local qty_text = "x" .. item.quantity
                love.graphics.print(qty_text, panel_x + panel_width - 35, item_y + 3)
            end
        end

        -- Scroll indicators
        if self.scroll_offset > 0 then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.print("▲", panel_x + panel_width/2 - 5, list_y - 12)
        end
        if self.scroll_offset + self.max_visible_items < #items then
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.print("▼", panel_x + panel_width/2 - 5, list_y + list_height - 5)
        end
    end

    -- Draw quantity selection overlay
    if self.quantity_mode and self.quantity_item then
        -- Dim background
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", panel_x, panel_y, panel_width, panel_height, 8, 8)

        -- Quantity dialog
        local dlg_width = 200
        local dlg_height = 100
        local dlg_x = panel_x + (panel_width - dlg_width) / 2
        local dlg_y = panel_y + (panel_height - dlg_height) / 2

        love.graphics.setColor(0.2, 0.2, 0.25, 1)
        love.graphics.rectangle("fill", dlg_x, dlg_y, dlg_width, dlg_height, 6, 6)
        love.graphics.setColor(0.5, 0.5, 0.6, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", dlg_x, dlg_y, dlg_width, dlg_height, 6, 6)

        -- Item name
        love.graphics.setColor(1, 1, 1, 1)
        local item_name = self:getItemName(self.quantity_item.type)
        local name_width = self.item_font:getWidth(item_name)
        love.graphics.print(item_name, dlg_x + (dlg_width - name_width) / 2, dlg_y + 10)

        -- Quantity selector
        local qty_y = dlg_y + 40
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print("◀", dlg_x + 30, qty_y)
        love.graphics.print("▶", dlg_x + dlg_width - 45, qty_y)

        love.graphics.setColor(1, 1, 1, 1)
        local qty_text = tostring(self.quantity)
        local qty_width = self.item_font:getWidth(qty_text)
        love.graphics.print(qty_text, dlg_x + (dlg_width - qty_width) / 2, qty_y)

        -- Total price
        local total_price
        if self.tab == "buy" then
            total_price = self.quantity_item.price * self.quantity
            love.graphics.setColor(1, 0.85, 0, 1)
            love.graphics.print("Total: " .. total_price .. "G", dlg_x + 20, dlg_y + 65)
        else
            total_price = (self.quantity_item.sell_price or 0) * self.quantity
            love.graphics.setColor(0.5, 0.8, 0.5, 1)
            love.graphics.print("Get: +" .. total_price .. "G", dlg_x + 20, dlg_y + 65)
        end

        -- Hint
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        love.graphics.print("[A] OK  [B] Cancel", dlg_x + dlg_width - 110, dlg_y + 65)
    end

    -- Draw message
    if self.message and not self.quantity_mode then
        love.graphics.setColor(0, 0, 0, 0.8)
        local msg_width = self.item_font:getWidth(self.message) + 20
        local msg_x = panel_x + (panel_width - msg_width) / 2
        local msg_y = panel_y + panel_height - 35
        love.graphics.rectangle("fill", msg_x, msg_y, msg_width, 22, 4, 4)

        love.graphics.setColor(1, 1, 0.5, 1)
        love.graphics.print(self.message, msg_x + 10, msg_y + 4)
    end

    -- Draw close button (only when not in quantity mode)
    if not self.quantity_mode then
        local close_x = panel_x + panel_width - self.close_button_size - self.close_button_padding
        local close_y = panel_y + self.close_button_padding
        shapes:drawCloseButton(close_x, close_y, self.close_button_size, self.close_button_hovered)
    end

    -- Draw controls hint
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.setFont(self.item_font)
    if self.quantity_mode then
        love.graphics.print("[←→] Qty  [↑↓] ±10  [A] OK  [B] Cancel", panel_x + 15, panel_y + panel_height - 18)
    else
        love.graphics.print("[A] Select  [B] Close  [LB/RB] Tab", panel_x + 20, panel_y + panel_height - 18)
    end

    display:Detach()
end

function shop_ui:mousemoved(x, y)
    local vx, vy = coords:physicalToVirtual(x, y)
    local vw, vh = display:GetVirtualDimensions()

    -- Check close button hover
    local panel_width = 300
    local panel_height = 280
    local panel_x = (vw - panel_width) / 2
    local panel_y = (vh - panel_height) / 2

    local close_x = panel_x + panel_width - self.close_button_size - self.close_button_padding
    local close_y = panel_y + self.close_button_padding

    self.close_button_hovered = vx >= close_x and vx <= close_x + self.close_button_size
        and vy >= close_y and vy <= close_y + self.close_button_size
end

function shop_ui:mousepressed(x, y, button)
    if button ~= 1 then return end

    local vx, vy = coords:physicalToVirtual(x, y)
    local vw, vh = display:GetVirtualDimensions()

    local panel_width = 300
    local panel_height = 280
    local panel_x = (vw - panel_width) / 2
    local panel_y = (vh - panel_height) / 2

    -- Quantity mode mouse handling
    if self.quantity_mode then
        local dlg_width = 200
        local dlg_height = 100
        local dlg_x = panel_x + (panel_width - dlg_width) / 2
        local dlg_y = panel_y + (panel_height - dlg_height) / 2

        -- Left arrow click
        if vx >= dlg_x + 20 and vx <= dlg_x + 50 and vy >= dlg_y + 35 and vy <= dlg_y + 55 then
            self:adjustQuantity(-1)
            return
        end
        -- Right arrow click
        if vx >= dlg_x + dlg_width - 50 and vx <= dlg_x + dlg_width - 20 and vy >= dlg_y + 35 and vy <= dlg_y + 55 then
            self:adjustQuantity(1)
            return
        end
        -- OK button area (bottom left)
        if vx >= dlg_x + 10 and vx <= dlg_x + 80 and vy >= dlg_y + 60 and vy <= dlg_y + 80 then
            self:executeTransaction()
            return
        end
        -- Cancel - click outside dialog
        if vx < dlg_x or vx > dlg_x + dlg_width or vy < dlg_y or vy > dlg_y + dlg_height then
            self:cancelQuantityMode()
            return
        end
        return
    end

    -- Close button
    if self.close_button_hovered then
        self:close()
        return
    end

    -- Tab clicks
    local tab_y = panel_y + 40
    local tab_width = 80
    local tab_height = 25

    local buy_x = panel_x + 30
    if vx >= buy_x and vx <= buy_x + tab_width and vy >= tab_y and vy <= tab_y + tab_height then
        self:switchTab("buy")
        return
    end

    local sell_x = panel_x + panel_width - tab_width - 30
    if vx >= sell_x and vx <= sell_x + tab_width and vy >= tab_y and vy <= tab_y + tab_height then
        self:switchTab("sell")
        return
    end

    -- Item clicks
    local list_y = tab_y + 35
    local item_height = 24
    local items = self:getCurrentItems()

    for i = 1, math.min(self.max_visible_items, #items - self.scroll_offset) do
        local idx = i + self.scroll_offset
        local item_y = list_y + (i - 1) * item_height

        if vx >= panel_x + 15 and vx <= panel_x + panel_width - 15
            and vy >= item_y and vy <= item_y + item_height then
            self.selected_index = idx
            self:confirmSelection()
            return
        end
    end
end

function shop_ui:wheelmoved(x, y)
    if self.quantity_mode then
        if y > 0 then
            self:adjustQuantity(1)
        elseif y < 0 then
            self:adjustQuantity(-1)
        end
    else
        if y > 0 then
            self:moveSelection(-1)
        elseif y < 0 then
            self:moveSelection(1)
        end
    end
end

function shop_ui:keypressed(key)
    if self.quantity_mode then
        if key == "escape" then
            self:cancelQuantityMode()
        elseif key == "left" then
            self:adjustQuantity(-1)
        elseif key == "right" then
            self:adjustQuantity(1)
        elseif key == "up" then
            self:adjustQuantity(10)
        elseif key == "down" then
            self:adjustQuantity(-10)
        elseif key == "return" or key == "space" then
            self:executeTransaction()
        end
        return
    end

    if key == "escape" then
        self:close()
    elseif key == "up" then
        self:moveSelection(-1)
    elseif key == "down" then
        self:moveSelection(1)
    elseif key == "return" or key == "space" then
        self:confirmSelection()
    elseif key == "tab" then
        -- Toggle tab
        self:switchTab(self.tab == "buy" and "sell" or "buy")
    end
end

function shop_ui:gamepadpressed(joystick, button)
    -- Quantity mode
    if self.quantity_mode then
        if button == "dpleft" then
            self:adjustQuantity(-1)
        elseif button == "dpright" then
            self:adjustQuantity(1)
        elseif button == "dpup" then
            self:adjustQuantity(10)
        elseif button == "dpdown" then
            self:adjustQuantity(-10)
        elseif button == "a" then
            self:executeTransaction()
        elseif button == "b" then
            self:cancelQuantityMode()
        end
        return
    end

    -- Normal mode
    if button == "dpup" then
        self:moveSelection(-1)
    elseif button == "dpdown" then
        self:moveSelection(1)
    elseif button == "a" then
        self:confirmSelection()
    elseif button == "b" or button == "start" then
        self:close()
    elseif button == "leftshoulder" then
        self:switchTab("buy")
    elseif button == "rightshoulder" then
        self:switchTab("sell")
    end
end

return shop_ui

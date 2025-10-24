-- scenes/inventory_ui.lua
-- Inventory UI window overlay

local inventory_ui = {}

local screen = require "lib.screen"
local input = require "systems.input"
local sound = require "systems.sound"

-- Safe sound wrapper
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

function inventory_ui:enter(previous, player_inventory, player)
    self.previous_scene = previous
    self.inventory = player_inventory
    self.player = player

    self.selected_slot = self.inventory.selected_slot
    self.max_visible_slots = 10

    self.slot_size = 80
    self.slot_spacing = 10
    self.padding = 40

    self.title_font = love.graphics.newFont(24)
    self.item_font = love.graphics.newFont(16)
    self.desc_font = love.graphics.newFont(14)

    play_sound("ui", "open")
end

function inventory_ui:exit()
    play_sound("ui", "close")
end

function inventory_ui:update(dt)
    -- No gameplay update while in inventory
end

function inventory_ui:keypressed(key)
    if key == "i" or key == "escape" or input:wasPressed("pause", "keyboard", key) then
        local scene_control = require "systems.scene_control"
        scene_control.pop()
    elseif key == "up" or key == "w" then
        self:moveSelection(-1)
    elseif key == "down" or key == "s" then
        self:moveSelection(1)
    elseif key == "return" or key == "space" or key == "e" then
        self:useSelectedItem()
    elseif key == "q" then
        self:useSelectedItem()
    elseif tonumber(key) then
        local slot_num = tonumber(key)
        if slot_num >= 1 and slot_num <= #self.inventory.items then
            self.selected_slot = slot_num
            self.inventory.selected_slot = slot_num
            play_sound("ui", "select")
        end
    end
end

function inventory_ui:mousepressed(x, y, button)
    if button == 1 then
        local vw, vh = screen:GetVirtualDimensions()
        local sw, sh = screen:GetScreenDimensions()

        -- Convert screen coordinates to virtual coordinates
        local mouse_vx = (x / sw) * vw
        local mouse_vy = (y / sh) * vh

        -- Check if clicked on a slot
        local start_x = (vw - (self.slot_size + self.slot_spacing) * math.min(#self.inventory.items, 5)) / 2
        local start_y = 150

        for i, item in ipairs(self.inventory.items) do
            local row = math.floor((i - 1) / 5)
            local col = (i - 1) % 5
            local slot_x = start_x + col * (self.slot_size + self.slot_spacing)
            local slot_y = start_y + row * (self.slot_size + self.slot_spacing)

            if mouse_vx >= slot_x and mouse_vx <= slot_x + self.slot_size and
                mouse_vy >= slot_y and mouse_vy <= slot_y + self.slot_size then
                self.selected_slot = i
                self.inventory.selected_slot = i
                play_sound("ui", "select")
                break
            end
        end
    elseif button == 2 then
        -- Right click to use item
        self:useSelectedItem()
    end
end

function inventory_ui:moveSelection(direction)
    if #self.inventory.items == 0 then return end

    self.selected_slot = self.selected_slot + direction
    if self.selected_slot < 1 then
        self.selected_slot = #self.inventory.items
    elseif self.selected_slot > #self.inventory.items then
        self.selected_slot = 1
    end

    self.inventory.selected_slot = self.selected_slot
    play_sound("ui", "select")
end

function inventory_ui:useSelectedItem()
    if self.inventory:useSelectedItem(self.player) then
        play_sound("ui", "use")
        print("Used item!")

        -- Update selected slot if item was consumed
        if self.selected_slot > #self.inventory.items and self.selected_slot > 1 then
            self.selected_slot = #self.inventory.items
            self.inventory.selected_slot = self.selected_slot
        end
    else
        play_sound("ui", "error")
    end
end

function inventory_ui:draw()
    -- Draw previous scene (dimmed)
    if self.previous_scene and self.previous_scene.draw then
        self.previous_scene:draw()
    end

    screen:Attach()

    local vw, vh = screen:GetVirtualDimensions()

    -- Draw dark overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, vw, vh)

    -- Draw window background
    local window_w = 600
    local window_h = 500
    local window_x = (vw - window_w) / 2
    local window_y = (vh - window_h) / 2

    love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
    love.graphics.rectangle("fill", window_x, window_y, window_w, window_h, 10, 10)

    love.graphics.setColor(0.3, 0.3, 0.4, 1)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", window_x, window_y, window_w, window_h, 10, 10)

    -- Draw title
    love.graphics.setFont(self.title_font)
    love.graphics.setColor(1, 1, 1, 1)
    local title = "INVENTORY"
    local title_w = self.title_font:getWidth(title)
    love.graphics.print(title, (vw - title_w) / 2, window_y + 20)

    -- Draw close instruction
    love.graphics.setFont(self.desc_font)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.print("Press [I] or [ESC] to close", window_x + 20, window_y + 20)

    -- Draw items in grid
    if #self.inventory.items == 0 then
        love.graphics.setFont(self.item_font)
        love.graphics.setColor(0.5, 0.5, 0.5, 1)
        local empty_text = "No items in inventory"
        local empty_w = self.item_font:getWidth(empty_text)
        love.graphics.print(empty_text, (vw - empty_w) / 2, vh / 2)
    else
        local start_x = (vw - (self.slot_size + self.slot_spacing) * math.min(#self.inventory.items, 5)) / 2
        local start_y = 150

        for i, item in ipairs(self.inventory.items) do
            local row = math.floor((i - 1) / 5)
            local col = (i - 1) % 5
            local x = start_x + col * (self.slot_size + self.slot_spacing)
            local y = start_y + row * (self.slot_size + self.slot_spacing)

            -- Draw slot background
            if i == self.selected_slot then
                love.graphics.setColor(0.4, 0.6, 1, 0.9)
            else
                love.graphics.setColor(0.2, 0.2, 0.3, 0.8)
            end
            love.graphics.rectangle("fill", x, y, self.slot_size, self.slot_size, 5, 5)

            -- Draw slot border
            if i == self.selected_slot then
                love.graphics.setColor(0.6, 0.8, 1, 1)
                love.graphics.setLineWidth(3)
            else
                love.graphics.setColor(0.4, 0.4, 0.5, 1)
                love.graphics.setLineWidth(1)
            end
            love.graphics.rectangle("line", x, y, self.slot_size, self.slot_size, 5, 5)

            -- Draw item icon (colored HP text)
            love.graphics.setFont(self.title_font)
            local icon_text = "HP"
            if item.type == "small_potion" then
                love.graphics.setColor(0.5, 1, 0.5, 1)
            elseif item.type == "large_potion" then
                love.graphics.setColor(0.3, 1, 0.8, 1)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            local icon_w = self.title_font:getWidth(icon_text)
            love.graphics.print(icon_text, x + (self.slot_size - icon_w) / 2, y + 15)

            -- Draw quantity
            love.graphics.setFont(self.item_font)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print("x" .. item.quantity, x + 8, y + self.slot_size - 25)

            -- Draw slot number
            love.graphics.setFont(self.desc_font)
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.print(tostring(i), x + 5, y + 5)
        end

        -- Draw selected item details
        if self.selected_slot >= 1 and self.selected_slot <= #self.inventory.items then
            local item = self.inventory.items[self.selected_slot]

            local detail_y = start_y + math.ceil(#self.inventory.items / 5) * (self.slot_size + self.slot_spacing) + 30

            love.graphics.setFont(self.item_font)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(item.name, window_x + 30, detail_y)

            love.graphics.setFont(self.desc_font)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.print(item.description, window_x + 30, detail_y + 25)

            -- Draw usage instructions
            love.graphics.setColor(0.6, 0.8, 1, 1)
            love.graphics.print("Press [E], [Q], [Space] or [Enter] to use", window_x + 30, detail_y + 50)

            -- Can use indicator
            if item:canUse(self.player) then
                love.graphics.setColor(0.3, 1, 0.3, 1)
                love.graphics.print("✓ Can use", window_x + 30, detail_y + 70)
            else
                love.graphics.setColor(1, 0.3, 0.3, 1)
                love.graphics.print("✗ Cannot use (HP full)", window_x + 30, detail_y + 70)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)

    screen:Detach()
end

return inventory_ui

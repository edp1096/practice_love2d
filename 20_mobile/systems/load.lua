-- systems/load.lua
-- Load game scene with save slot selection, delete confirmation, and gamepad support

local load = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local save_sys = require "systems.save"
local input = require "systems.input"

function load:enter(previous, ...)
    self.previous = previous
    self.selected = 1

    -- Hide virtual gamepad in load menu
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    self.titleFont = love.graphics.newFont(36)
    self.slotFont = love.graphics.newFont(24)
    self.infoFont = love.graphics.newFont(16)
    self.hintFont = love.graphics.newFont(14)
    self.confirmFont = love.graphics.newFont(20)

    self.slots = save_sys:getAllSlotsInfo()

    table.insert(self.slots, {
        exists = false,
        slot = "back",
        display_name = "Back to Menu"
    })

    self.layout = {
        title_y = vh * 0.12,
        slots_start_y = vh * 0.25,
        slot_spacing = 90,
        hint_y = vh - 40
    }

    self.mouse_over = 0
    self.mouse_over_delete = 0
    self.confirm_delete = false
    self.delete_slot = nil
    self.confirm_selected = 1 -- 1 = No, 2 = Yes
    self.confirm_mouse_over = 0
end

function load:update(dt)
    if self.confirm_delete then
        -- Check Yes/No button hover
        local vmx, vmy = screen:GetVirtualMousePosition()
        self.confirm_mouse_over = 0

        local button_y = self.virtual_height / 2 + 60
        local button_width = 120
        local button_height = 50
        local button_spacing = 40

        -- No button (left)
        local no_x = self.virtual_width / 2 - button_width - button_spacing / 2
        if vmx >= no_x and vmx <= no_x + button_width and
            vmy >= button_y and vmy <= button_y + button_height then
            self.confirm_mouse_over = 1
        end

        -- Yes button (right)
        local yes_x = self.virtual_width / 2 + button_spacing / 2
        if vmx >= yes_x and vmx <= yes_x + button_width and
            vmy >= button_y and vmy <= button_y + button_height then
            self.confirm_mouse_over = 2
        end

        return
    end

    local vmx, vmy = screen:GetVirtualMousePosition()

    self.mouse_over = 0
    self.mouse_over_delete = 0

    for i, slot in ipairs(self.slots) do
        local y = self.layout.slots_start_y + (i - 1) * self.layout.slot_spacing
        local slot_height = 80
        local padding = 10

        -- Check X button hover (only for existing slots, not back button)
        if slot.exists and slot.slot ~= "back" then
            local delete_x = self.virtual_width * 0.15 + self.virtual_width * 0.7 - 40
            local delete_y = y + 5
            local delete_size = 30

            if vmx >= delete_x and vmx <= delete_x + delete_size and
                vmy >= delete_y and vmy <= delete_y + delete_size then
                self.mouse_over_delete = i
            end
        end

        -- Check slot hover
        if vmy >= y - padding and vmy <= y + slot_height + padding then
            if self.mouse_over_delete == 0 then
                self.mouse_over = i
            end
        end
    end
end

function load:draw()
    love.graphics.clear(0.1, 0.1, 0.15, 1)

    screen:Attach()

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setFont(self.titleFont)
    love.graphics.printf("Load Game", 0, self.layout.title_y, self.virtual_width, "center")

    for i, slot in ipairs(self.slots) do
        local y = self.layout.slots_start_y + (i - 1) * self.layout.slot_spacing
        local is_selected = (i == self.selected or i == self.mouse_over)

        if is_selected then
            love.graphics.setColor(0.3, 0.3, 0.4, 0.8)
        else
            love.graphics.setColor(0.2, 0.2, 0.25, 0.6)
        end
        love.graphics.rectangle("fill", self.virtual_width * 0.15, y - 5, self.virtual_width * 0.7, 80)

        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.rectangle("line", self.virtual_width * 0.15, y - 5, self.virtual_width * 0.7, 80)

        if slot.slot == "back" then
            love.graphics.setFont(self.slotFont)
            if is_selected then
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
            end
            love.graphics.printf(slot.display_name, 0, y + 25, self.virtual_width, "center")
        elseif slot.exists then
            love.graphics.setFont(self.slotFont)
            if is_selected then
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            love.graphics.print("Slot " .. slot.slot, self.virtual_width * 0.2, y)

            love.graphics.setFont(self.infoFont)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.print("HP: " .. slot.hp .. "/" .. slot.max_hp, self.virtual_width * 0.2, y + 28)
            love.graphics.print(slot.map_display or "Unknown", self.virtual_width * 0.2, y + 48)

            love.graphics.setFont(self.hintFont)
            love.graphics.setColor(0.6, 0.6, 0.6, 1)
            love.graphics.print(slot.time_string, self.virtual_width * 0.2, y + 65)

            -- Draw X delete button
            local delete_x = self.virtual_width * 0.15 + self.virtual_width * 0.7 - 40
            local delete_y = y + 5
            local delete_size = 30
            local is_delete_hovered = (self.mouse_over_delete == i)

            -- Button background
            if is_delete_hovered then
                love.graphics.setColor(0.8, 0.2, 0.2, 0.9)
            else
                love.graphics.setColor(0.5, 0.2, 0.2, 0.7)
            end
            love.graphics.rectangle("fill", delete_x, delete_y, delete_size, delete_size)

            -- Button border
            if is_delete_hovered then
                love.graphics.setColor(1, 0.3, 0.3, 1)
            else
                love.graphics.setColor(0.7, 0.3, 0.3, 1)
            end
            love.graphics.rectangle("line", delete_x, delete_y, delete_size, delete_size)

            -- X mark
            love.graphics.setFont(self.slotFont)
            if is_delete_hovered then
                love.graphics.setColor(1, 1, 1, 1)
            else
                love.graphics.setColor(0.9, 0.9, 0.9, 0.9)
            end
            love.graphics.print("X", delete_x + 8, delete_y + 2)
        else
            love.graphics.setFont(self.slotFont)
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
            love.graphics.print("Slot " .. slot.slot .. " - Empty", self.virtual_width * 0.2, y + 25)
        end
    end

    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)

    if input:hasGamepad() then
        love.graphics.printf("D-Pad: Navigate | " .. input:getPrompt("menu_select") .. ": Load | " .. input:getPrompt("menu_back") .. ": Back | " .. input:getPrompt("quicksave_1") .. input:getPrompt("quicksave_2") .. ": Quick Delete",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("Keyboard: Arrow Keys / WASD | Enter: Load | ESC: Back | Delete: Delete | Mouse: Hover & Click [X]",
            0, self.layout.hint_y, self.virtual_width, "center")
    else
        love.graphics.printf("Arrow Keys / WASD: Navigate | Enter: Select | ESC: Back | Delete: Delete Save",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("Mouse: Hover and Click | Click [X] button to delete",
            0, self.layout.hint_y, self.virtual_width, "center")
    end

    if self.confirm_delete and self.delete_slot then
        love.graphics.setColor(0, 0, 0, 0.85)
        love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)

        love.graphics.setFont(self.confirmFont)
        love.graphics.setColor(1, 0.3, 0.3, 1)
        local confirm_text = "Delete Slot " .. self.delete_slot .. "?"
        love.graphics.printf(confirm_text, 0, self.virtual_height / 2 - 60, self.virtual_width, "center")

        love.graphics.setFont(self.hintFont)
        love.graphics.setColor(0.9, 0.9, 0.9, 1)
        love.graphics.printf("This action cannot be undone!", 0, self.virtual_height / 2 - 20, self.virtual_width, "center")

        -- Draw Yes/No buttons
        local button_y = self.virtual_height / 2 + 60
        local button_width = 120
        local button_height = 50
        local button_spacing = 40

        -- No button (left)
        local no_x = self.virtual_width / 2 - button_width - button_spacing / 2
        local is_no_selected = (self.confirm_selected == 1 or self.confirm_mouse_over == 1)

        if is_no_selected then
            love.graphics.setColor(0.4, 0.4, 0.5, 0.9)
        else
            love.graphics.setColor(0.3, 0.3, 0.35, 0.7)
        end
        love.graphics.rectangle("fill", no_x, button_y, button_width, button_height)

        if is_no_selected then
            love.graphics.setColor(0.7, 0.7, 0.8, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.rectangle("line", no_x, button_y, button_width, button_height)

        love.graphics.setFont(self.slotFont)
        if is_no_selected then
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
        end
        love.graphics.printf("No", no_x, button_y + 12, button_width, "center")

        -- Yes button (right)
        local yes_x = self.virtual_width / 2 + button_spacing / 2
        local is_yes_selected = (self.confirm_selected == 2 or self.confirm_mouse_over == 2)

        if is_yes_selected then
            love.graphics.setColor(0.8, 0.2, 0.2, 0.9)
        else
            love.graphics.setColor(0.5, 0.2, 0.2, 0.7)
        end
        love.graphics.rectangle("fill", yes_x, button_y, button_width, button_height)

        if is_yes_selected then
            love.graphics.setColor(1, 0.3, 0.3, 1)
        else
            love.graphics.setColor(0.7, 0.3, 0.3, 1)
        end
        love.graphics.rectangle("line", yes_x, button_y, button_width, button_height)

        love.graphics.setFont(self.slotFont)
        if is_yes_selected then
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(0.9, 0.9, 0.9, 0.9)
        end
        love.graphics.printf("Yes", yes_x, button_y + 12, button_width, "center")

        -- Hint text
        love.graphics.setFont(self.hintFont)
        love.graphics.setColor(0.7, 0.7, 0.7, 1)

        if input:hasGamepad() then
            love.graphics.printf(input:getPrompt("menu_left") .. input:getPrompt("menu_right") .. ": Select | " .. input:getPrompt("menu_select") .. ": Confirm | " .. input:getPrompt("menu_back") .. ": Cancel",
                0, button_y + button_height + 30, self.virtual_width, "center")
            love.graphics.printf("Or use keyboard/mouse",
                0, button_y + button_height + 50, self.virtual_width, "center")
        else
            love.graphics.printf("Arrow Keys / WASD to select | Enter to confirm | ESC to cancel",
                0, button_y + button_height + 30, self.virtual_width, "center")
            love.graphics.printf("Or click a button with mouse",
                0, button_y + button_height + 50, self.virtual_width, "center")
        end
    end

    screen:Detach()
end

function load:resize(w, h)
    screen:Resize(w, h)
end

function load:keypressed(key)
    if self.confirm_delete then
        if key == "left" or key == "a" then
            self.confirm_selected = 1 -- No
        elseif key == "right" or key == "d" then
            self.confirm_selected = 2 -- Yes
        elseif key == "return" or key == "space" then
            if self.confirm_selected == 2 then
                -- Yes - delete
                save_sys:deleteSlot(self.delete_slot)
                self.slots = save_sys:getAllSlotsInfo()
                table.insert(self.slots, {
                    exists = false,
                    slot = "back",
                    display_name = "Back to Menu"
                })
                print("Deleted save slot " .. self.delete_slot)
            else
                -- No - cancel
                print("Delete cancelled")
            end
            self.confirm_delete = false
            self.delete_slot = nil
            self.confirm_selected = 1
        elseif key == "escape" then
            self.confirm_delete = false
            self.delete_slot = nil
            self.confirm_selected = 1
            print("Delete cancelled")
        end
        return
    end

    if key == "up" or key == "w" then
        self.selected = self.selected - 1
        if self.selected < 1 then
            self.selected = #self.slots
        end
    elseif key == "down" or key == "s" then
        self.selected = self.selected + 1
        if self.selected > #self.slots then
            self.selected = 1
        end
    elseif key == "return" or key == "space" then
        self:selectSlot(self.selected)
    elseif key == "escape" then
        local menu = require "scenes.menu"
        scene_control.switch(menu)
    elseif key == "delete" then
        local slot = self.slots[self.selected]
        if slot and slot.exists and slot.slot ~= "back" then
            self.confirm_delete = true
            self.delete_slot = slot.slot
            self.confirm_selected = 1 -- Default to No
        end
    end
end

function load:gamepadpressed(joystick, button)
    if self.confirm_delete then
        -- Delete confirmation dialog
        if input:wasPressed("menu_left", "gamepad", button) then
            self.confirm_selected = 1 -- No
        elseif input:wasPressed("menu_right", "gamepad", button) then
            self.confirm_selected = 2 -- Yes
        elseif input:wasPressed("menu_select", "gamepad", button) then
            if self.confirm_selected == 2 then
                -- Yes - delete
                save_sys:deleteSlot(self.delete_slot)
                self.slots = save_sys:getAllSlotsInfo()
                table.insert(self.slots, {
                    exists = false,
                    slot = "back",
                    display_name = "Back to Menu"
                })
                print("Deleted save slot " .. self.delete_slot)
            else
                -- No - cancel
                print("Delete cancelled")
            end
            self.confirm_delete = false
            self.delete_slot = nil
            self.confirm_selected = 1
        elseif input:wasPressed("menu_back", "gamepad", button) then
            self.confirm_delete = false
            self.delete_slot = nil
            self.confirm_selected = 1
            print("Delete cancelled")
        end
        return
    end

    -- Normal navigation
    if input:wasPressed("menu_up", "gamepad", button) then
        self.selected = self.selected - 1
        if self.selected < 1 then
            self.selected = #self.slots
        end
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.selected = self.selected + 1
        if self.selected > #self.slots then
            self.selected = 1
        end
    elseif input:wasPressed("menu_select", "gamepad", button) then
        self:selectSlot(self.selected)
    elseif input:wasPressed("menu_back", "gamepad", button) then
        local menu = require "scenes.menu"
        scene_control.switch(menu)
    elseif input:wasPressed("quicksave_1", "gamepad", button) then
        -- L1 - delete slot 1 (if exists and selected)
        local slot = self.slots[1]
        if slot and slot.exists and slot.slot ~= "back" then
            self.selected = 1
            self.confirm_delete = true
            self.delete_slot = slot.slot
            self.confirm_selected = 1
        end
    elseif input:wasPressed("quicksave_2", "gamepad", button) then
        -- R1 - delete slot 2 (if exists and selected)
        local slot = self.slots[2]
        if slot and slot.exists and slot.slot ~= "back" then
            self.selected = 2
            self.confirm_delete = true
            self.delete_slot = slot.slot
            self.confirm_selected = 1
        end
    end
end

function load:selectSlot(slot_index)
    local slot = self.slots[slot_index]

    if slot.slot == "back" then
        local menu = require "scenes.menu"
        scene_control.switch(menu)
    elseif slot.exists then
        local play = require "scenes.play"
        scene_control.switch(play, slot.map, slot.x, slot.y, slot.slot)
    else
        print("Cannot load empty slot")
    end
end

function load:mousepressed(x, y, button) end

function load:mousereleased(x, y, button)
    if button ~= 1 then return end

    if self.confirm_delete then
        -- Check Yes/No button clicks
        if self.confirm_mouse_over == 1 then
            -- No button - cancel
            self.confirm_delete = false
            self.delete_slot = nil
            self.confirm_selected = 1
            print("Delete cancelled")
        elseif self.confirm_mouse_over == 2 then
            -- Yes button - delete
            save_sys:deleteSlot(self.delete_slot)
            self.slots = save_sys:getAllSlotsInfo()
            table.insert(self.slots, {
                exists = false,
                slot = "back",
                display_name = "Back to Menu"
            })
            print("Deleted save slot " .. self.delete_slot)
            self.confirm_delete = false
            self.delete_slot = nil
            self.confirm_selected = 1
        end
        return
    end

    -- Check if X button was clicked
    if self.mouse_over_delete > 0 then
        local slot = self.slots[self.mouse_over_delete]
        if slot and slot.exists and slot.slot ~= "back" then
            self.confirm_delete = true
            self.delete_slot = slot.slot
            self.confirm_selected = 1 -- Default to No
        end
        -- Normal slot click
    elseif self.mouse_over > 0 then
        self.selected = self.mouse_over
        self:selectSlot(self.selected)
    end
end

return load

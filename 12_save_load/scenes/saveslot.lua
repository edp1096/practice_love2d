-- scenes/saveslot.lua
-- Save slot selection scene (shown when pressing F at save point)

local saveslot = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local save_sys = require "systems.save"

function saveslot:enter(previous, save_callback, ...)
    self.previous = previous
    self.save_callback = save_callback
    self.selected = 1

    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    self.titleFont = love.graphics.newFont(36)
    self.slotFont = love.graphics.newFont(24)
    self.infoFont = love.graphics.newFont(16)
    self.hintFont = love.graphics.newFont(14)

    -- Load save slot information
    self.slots = save_sys:getAllSlotsInfo()

    -- Add "Cancel" option
    table.insert(self.slots, {
        exists = false,
        slot = "cancel",
        display_name = "Cancel"
    })

    -- Layout
    self.layout = {
        title_y = vh * 0.12,
        slots_start_y = vh * 0.25,
        slot_spacing = 90,
        hint_y = vh - 40
    }

    self.mouse_over = 0

    -- Fade in overlay
    self.overlay_alpha = 0
    self.target_alpha = 0.85
end

function saveslot:update(dt)
    -- Fade in overlay
    if self.overlay_alpha < self.target_alpha then
        self.overlay_alpha = math.min(self.overlay_alpha + dt * 3, self.target_alpha)
    end

    local vmx, vmy = screen:GetVirtualMousePosition()

    self.mouse_over = 0

    for i, slot in ipairs(self.slots) do
        local y = self.layout.slots_start_y + (i - 1) * self.layout.slot_spacing
        local slot_height = 80
        local padding = 10

        if vmy >= y - padding and vmy <= y + slot_height + padding then
            self.mouse_over = i
            break
        end
    end
end

function saveslot:draw()
    -- Draw previous scene in background (dimmed)
    if self.previous and self.previous.draw then
        local success, err = pcall(function()
            self.previous:draw()
        end)

        if not success then
            love.graphics.clear(0, 0, 0, 1)
        end
    end

    screen:Attach()

    -- Dark overlay
    love.graphics.setColor(0, 0, 0, self.overlay_alpha)
    love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)

    love.graphics.setColor(1, 1, 1, 1)

    -- Title
    love.graphics.setFont(self.titleFont)
    love.graphics.printf("Select Save Slot", 0, self.layout.title_y, self.virtual_width, "center")

    -- Draw save slots
    for i, slot in ipairs(self.slots) do
        local y = self.layout.slots_start_y + (i - 1) * self.layout.slot_spacing
        local is_selected = (i == self.selected or i == self.mouse_over)

        -- Slot background
        if is_selected then
            love.graphics.setColor(0.3, 0.3, 0.4, 0.9)
        else
            love.graphics.setColor(0.2, 0.2, 0.25, 0.7)
        end
        love.graphics.rectangle("fill", self.virtual_width * 0.15, y - 5, self.virtual_width * 0.7, 80)

        -- Border
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, 1)
        end
        love.graphics.rectangle("line", self.virtual_width * 0.15, y - 5, self.virtual_width * 0.7, 80)

        if slot.slot == "cancel" then
            -- Cancel button
            love.graphics.setFont(self.slotFont)
            if is_selected then
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(0.8, 0.8, 0.8, 1)
            end
            love.graphics.printf(slot.display_name, 0, y + 25, self.virtual_width, "center")
        elseif slot.exists then
            -- Existing save (will be overwritten)
            love.graphics.setFont(self.slotFont)
            if is_selected then
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            love.graphics.print("Slot " .. slot.slot .. " (Overwrite)", self.virtual_width * 0.2, y)

            love.graphics.setFont(self.infoFont)
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
            love.graphics.print("HP: " .. slot.hp .. "/" .. slot.max_hp, self.virtual_width * 0.2, y + 28)
            love.graphics.print(slot.time_string, self.virtual_width * 0.2, y + 48)
        else
            -- Empty slot
            love.graphics.setFont(self.slotFont)
            if is_selected then
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(0.7, 0.7, 0.7, 1)
            end
            love.graphics.print("Slot " .. slot.slot .. " - Empty", self.virtual_width * 0.2, y + 25)
        end
    end

    -- Controls hint
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Arrow Keys / WASD: Navigate | Enter: Save | ESC: Cancel",
        0, self.layout.hint_y - 20, self.virtual_width, "center")
    love.graphics.printf("Mouse: Hover and Click | F1/F2/F3: Quick Save to Slot",
        0, self.layout.hint_y, self.virtual_width, "center")

    screen:Detach()
end

function saveslot:resize(w, h)
    screen:Resize(w, h)
end

function saveslot:keypressed(key)
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
    elseif key == "escape" or key == "f" then
        -- Cancel
        scene_control.pop()
    elseif key == "f1" then
        -- Quick save to slot 1
        self:selectSlot(1)
    elseif key == "f2" then
        -- Quick save to slot 2
        self:selectSlot(2)
    elseif key == "f3" then
        -- Quick save to slot 3
        self:selectSlot(3)
    end
end

function saveslot:selectSlot(slot_index)
    local slot = self.slots[slot_index]

    if slot.slot == "cancel" then
        -- Cancel
        scene_control.pop()
    else
        -- Save to selected slot
        if self.save_callback then
            self.save_callback(slot.slot)
        end
        scene_control.pop()
    end
end

function saveslot:mousepressed(x, y, button) end

function saveslot:mousereleased(x, y, button)
    if button == 1 then
        if self.mouse_over > 0 then
            self.selected = self.mouse_over
            self:selectSlot(self.selected)
        end
    end
end

return saveslot

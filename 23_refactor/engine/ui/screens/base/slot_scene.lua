-- engine/ui/screens/base/slot_scene.lua
-- Base class for slot-based UI screens (newgame, saveslot, load)

local slot_scene = {}
slot_scene.__index = slot_scene

local display = require "engine.core.display"
local save_sys = require "engine.core.save"
local input = require "engine.core.input"
local fonts = require "engine.utils.fonts"
local debug = require "engine.core.debug"
local shapes = require "engine.utils.shapes"
local text_ui = require "engine.utils.text"
local scene_control = require "engine.core.scene_control"

-- Create a new slot scene instance
function slot_scene:new()
    local instance = {}
    setmetatable(instance, self)
    return instance
end

-- Common enter logic
function slot_scene:enter(previous, ...)
    self.previous = previous
    self.selected = 1

    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    -- Initialize fonts
    self.titleFont = fonts.title
    self.slotFont = fonts.option
    self.infoFont = fonts.info
    self.hintFont = fonts.hint

    -- Load slots
    self.slots = save_sys:getAllSlotsInfo()

    -- Add back option if enabled
    if self:shouldAddBackOption() then
        table.insert(self.slots, {
            exists = false,
            slot = "back",
            display_name = "Back to Menu"
        })
    end

    -- Create layout
    self.layout = self:createLayout(vh)

    self.mouse_over = 0

    -- Call child-specific initialization
    if self.onEnter then
        self:onEnter(...)
    end
end

-- Override in child classes to customize layout
function slot_scene:createLayout(vh)
    return {
        title_y = vh * 0.10,
        slots_start_y = vh * 0.22,
        slot_spacing = 85,
        hint_y = vh - 30
    }
end

-- Override in child classes
function slot_scene:shouldAddBackOption()
    return true
end

-- Override in child classes to return scene title
function slot_scene:getTitle()
    return "Select Save Slot"
end

-- Common update logic - mouse over detection
function slot_scene:update(dt)
    local vmx, vmy = display:GetVirtualMousePosition()

    local previous_mouse_over = self.mouse_over
    self.mouse_over = 0

    for i, slot in ipairs(self.slots) do
        local y = self.layout.slots_start_y + (i - 1) * self.layout.slot_spacing
        local slot_height = 75
        local padding = 8

        if vmy >= y - padding and vmy <= y + slot_height + padding then
            self.mouse_over = i
            break
        end
    end

    -- Update selection when mouse hovers over a different slot
    if self.mouse_over ~= previous_mouse_over and self.mouse_over > 0 then
        self.selected = self.mouse_over
    end
end

-- Draw slot info (HP, map, time)
function slot_scene:drawSlotInfo(slot, y)
    text_ui:draw("HP: " .. slot.hp .. "/" .. slot.max_hp,
                 self.virtual_width * 0.2, y + 24, {0.8, 0.8, 0.8, 1}, self.infoFont)
    text_ui:draw(slot.map_display or "Unknown",
                 self.virtual_width * 0.2, y + 41, {0.8, 0.8, 0.8, 1}, self.infoFont)
    text_ui:draw(slot.time_string,
                 self.virtual_width * 0.2, y + 58, {0.6, 0.6, 0.6, 1}, self.hintFont)
end

-- Override in child classes to customize slot rendering
function slot_scene:drawSlot(slot, i, y, is_selected)
    -- Draw slot box
    local is_hovered = (i == self.mouse_over)
    local state = is_selected and "selected" or (is_hovered and "hover" or "normal")
    shapes:drawButton(self.virtual_width * 0.15, y - 5, self.virtual_width * 0.7, 75, state, 0)

    if slot.slot == "back" then
        love.graphics.setFont(self.slotFont)
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
        end
        love.graphics.printf(slot.display_name, 0, y + 24, self.virtual_width, "center")
    elseif slot.exists then
        local title_color = is_selected and {1, 0.7, 0, 1} or {1, 1, 1, 1}
        text_ui:draw("Slot " .. slot.slot, self.virtual_width * 0.2, y, title_color, self.slotFont)
        self:drawSlotInfo(slot, y)
    else
        local new_color = is_selected and {0, 1, 0.5, 1} or {0.7, 0.7, 0.7, 1}
        text_ui:draw("Slot " .. slot.slot .. " - Empty",
                     self.virtual_width * 0.2, y + 24, new_color, self.slotFont)
    end
end

-- Common draw logic
function slot_scene:draw()
    love.graphics.clear(0.1, 0.1, 0.15, 1)

    display:Attach()

    love.graphics.setColor(1, 1, 1, 1)

    -- Draw title
    love.graphics.setFont(self.titleFont)
    love.graphics.printf(self:getTitle(), 0, self.layout.title_y, self.virtual_width, "center")

    -- Draw slots
    for i, slot in ipairs(self.slots) do
        local y = self.layout.slots_start_y + (i - 1) * self.layout.slot_spacing
        local is_selected = (i == self.selected)
        self:drawSlot(slot, i, y, is_selected)
    end

    -- Draw hints
    self:drawHints()

    display:Detach()
end

-- Draw input hints
function slot_scene:drawHints()
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)

    local action_label = self:getActionLabel()

    if input:hasGamepad() then
        love.graphics.printf("D-Pad: Navigate | " ..
            input:getPrompt("menu_select") .. ": " .. action_label .. " | " ..
            input:getPrompt("menu_back") .. ": Back",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("Keyboard: Arrow Keys / WASD | Enter: " .. action_label .. " | ESC: Back | Mouse: Hover & Click",
            0, self.layout.hint_y, self.virtual_width, "center")
    else
        love.graphics.printf("Arrow Keys / WASD: Navigate | Enter: " .. action_label .. " | ESC: Back",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("Mouse: Hover and Click",
            0, self.layout.hint_y, self.virtual_width, "center")
    end
end

-- Override in child classes
function slot_scene:getActionLabel()
    return "Select"
end

-- Common resize logic
function slot_scene:resize(w, h)
    display:Resize(w, h)
end

-- Common keyboard navigation
function slot_scene:keypressed(key)
    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process scene keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if key == "up" or key == "w" then
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.slots end
    elseif key == "down" or key == "s" then
        self.selected = self.selected + 1
        if self.selected > #self.slots then self.selected = 1 end
    elseif key == "return" or key == "space" then
        self:selectSlot(self.selected)
    elseif key == "escape" then
        self:onBack()
    end
end

-- Common gamepad navigation
function slot_scene:gamepadpressed(joystick, button)
    if input:wasPressed("menu_up", "gamepad", button) then
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.slots end
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.selected = self.selected + 1
        if self.selected > #self.slots then self.selected = 1 end
    elseif input:wasPressed("menu_select", "gamepad", button) then
        self:selectSlot(self.selected)
    elseif input:wasPressed("menu_back", "gamepad", button) then
        self:onBack()
    end
end

-- Common mouse handling
function slot_scene:mousepressed(x, y, button) end

function slot_scene:mousereleased(x, y, button)
    if button == 1 then
        if self.mouse_over > 0 then
            self.selected = self.mouse_over
            self:selectSlot(self.selected)
        end
    end
end

-- Common touch handling
function slot_scene:touchpressed(id, x, y, dx, dy, pressure)
    local ui_helpers = require "engine.ui.menu.helpers"
    self.mouse_over = ui_helpers.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)
    return false
end

function slot_scene:touchreleased(id, x, y, dx, dy, pressure)
    local ui_helpers = require "engine.ui.menu.helpers"
    local touched = ui_helpers.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)

    if touched > 0 then
        self.selected = touched
        self:selectSlot(self.selected)
    end
    return false
end

-- Override in child classes - implement slot selection logic
function slot_scene:selectSlot(slot_index)
    error("selectSlot() must be implemented in child class")
end

-- Override in child classes - implement back action
function slot_scene:onBack()
    scene_control.switch("menu")
end

return slot_scene

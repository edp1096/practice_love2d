-- engine/ui/screens/saveslot.lua
-- Save slot selection scene (overlay on gameplay)

local SlotSceneBase = require "engine.ui.screens.base.slot_scene"
local saveslot = SlotSceneBase:new()

local scene_control = require "engine.core.scene_control"
local display = require "engine.core.display"
local input = require "engine.core.input"
local text_ui = require "engine.utils.text"

-- Initialize with save callback
function saveslot:onEnter(save_callback, ...)
    self.save_callback = save_callback

    -- Override "back" slot to "cancel"
    for i, slot in ipairs(self.slots) do
        if slot.slot == "back" then
            slot.slot = "cancel"
            slot.display_name = "Cancel"
        end
    end

    -- Overlay fade-in animation
    self.overlay_alpha = 0
    self.target_alpha = 0.85
end

-- Override to not add "back" option (we use "cancel" instead)
function saveslot:shouldAddBackOption()
    return true  -- We still add it, but customize it in onEnter
end

-- Customize title
function saveslot:getTitle()
    return "Save Game"
end

-- Customize action label
function saveslot:getActionLabel()
    return "Save"
end

-- Update with overlay fade-in
function saveslot:update(dt)
    -- Fade in overlay
    if self.overlay_alpha < self.target_alpha then
        self.overlay_alpha = math.min(self.overlay_alpha + dt * 3, self.target_alpha)
    end

    -- Call base update for mouse-over detection
    SlotSceneBase.update(self, dt)
end

-- Draw with background overlay
function saveslot:draw()
    -- Draw previous scene (gameplay) in background
    if self.previous and self.previous.draw then
        local success, err = pcall(function()
            self.previous:draw()
        end)

        if not success then
            love.graphics.clear(0, 0, 0, 1)
        end
    end

    display:Attach()

    -- Draw dark overlay
    love.graphics.setColor(0, 0, 0, self.overlay_alpha)
    love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)

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

    -- Draw hints (with quicksave shortcuts)
    self:drawHints()

    display:Detach()
end

-- Override slot rendering for save-specific display
function saveslot:drawSlot(slot, i, y, is_selected)
    local shapes = require "engine.utils.shapes"
    local is_hovered = (i == self.mouse_over)
    local state = is_selected and "selected" or (is_hovered and "hover" or "normal")
    shapes:drawButton(self.virtual_width * 0.15, y - 5, self.virtual_width * 0.7, 75, state, 0)

    if slot.slot == "cancel" then
        love.graphics.setFont(self.slotFont)
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
        end
        love.graphics.printf(slot.display_name, 0, y + 24, self.virtual_width, "center")
    elseif slot.exists then
        -- Show existing save data
        local title_color = is_selected and {1, 0.7, 0, 1} or {1, 1, 1, 1}
        text_ui:draw("Slot " .. slot.slot, self.virtual_width * 0.2, y, title_color, self.slotFont)
        self:drawSlotInfo(slot, y)
    else
        -- Empty slot
        local new_color = is_selected and {0, 1, 0.5, 1} or {0.7, 0.7, 0.7, 1}
        text_ui:draw("Slot " .. slot.slot .. " - Empty", self.virtual_width * 0.2, y + 24, new_color, self.slotFont)
    end
end

-- Override hints to show quicksave shortcuts
function saveslot:drawHints()
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)

    if input:hasGamepad() then
        love.graphics.printf("D-Pad: Navigate | " ..
            input:getPrompt("menu_select") .. ": Save | " ..
            input:getPrompt("menu_back") .. ": Cancel",
            0, self.layout.hint_y - 40, self.virtual_width, "center")
        love.graphics.printf("Keyboard: Arrow/WASD | Enter: Save | ESC/F: Cancel",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("F1/F2/F3: Quick Save to Slot | Mouse: Hover & Click",
            0, self.layout.hint_y, self.virtual_width, "center")
    else
        love.graphics.printf("Arrow Keys / WASD: Navigate | Enter: Save | ESC/F: Cancel",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("F1/F2/F3: Quick Save to Slot | Mouse: Hover & Click",
            0, self.layout.hint_y, self.virtual_width, "center")
    end
end

-- Override keyboard input for quicksave and ESC/F cancel
function saveslot:keypressed(key)
    local debug = require "engine.core.debug"
    debug:handleInput(key, {})

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
    elseif key == "escape" or key == "f" then
        scene_control.pop()
    elseif key == "f1" then
        self:selectSlot(1)
    elseif key == "f2" then
        self:selectSlot(2)
    elseif key == "f3" then
        self:selectSlot(3)
    end
end

-- Override gamepad input for quicksave
function saveslot:gamepadpressed(joystick, button)
    if input:wasPressed("menu_up", "gamepad", button) then
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.slots end
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.selected = self.selected + 1
        if self.selected > #self.slots then self.selected = 1 end
    elseif input:wasPressed("menu_select", "gamepad", button) then
        self:selectSlot(self.selected)
    elseif input:wasPressed("menu_back", "gamepad", button) then
        scene_control.pop()
    elseif input:wasPressed("quicksave_1", "gamepad", button) then
        self:selectSlot(1)
    elseif input:wasPressed("quicksave_2", "gamepad", button) then
        self:selectSlot(2)
    end
end

-- Implement slot selection
function saveslot:selectSlot(slot_index)
    local slot = self.slots[slot_index]

    if slot.slot == "cancel" then
        scene_control.pop()
    else
        if self.save_callback then
            self.save_callback(slot.slot)
        end
        scene_control.pop()
    end
end

-- Override back action
function saveslot:onBack()
    scene_control.pop()
end

return saveslot

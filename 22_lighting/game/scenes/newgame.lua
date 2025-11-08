-- scenes/newgame.lua
-- New game slot selection scene with level/area display and gamepad

local newgame = {}

local scene_control = require "engine.scene_control"
local display = require "engine.display"
local save_sys = require "engine.save"
local input = require "engine.input"
local constants = require "engine.constants"
local fonts = require "engine.utils.fonts"
local debug = require "engine.debug"
local shapes = require "engine.ui.shapes"
local text_ui = require "engine.ui.text"

function newgame:enter(previous, ...)
    self.previous = previous
    self.selected = 1

    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    self.titleFont = fonts.title
    self.slotFont = fonts.option
    self.infoFont = fonts.info
    self.hintFont = fonts.hint

    self.slots = save_sys:getAllSlotsInfo()

    table.insert(self.slots, {
        exists = false,
        slot = "back",
        display_name = "Back to Menu"
    })

    self.layout = {
        title_y = vh * 0.10,
        slots_start_y = vh * 0.22,
        slot_spacing = 85,
        hint_y = vh - 30
    }

    self.mouse_over = 0
end

function newgame:update(dt)
    local vmx, vmy = display:GetVirtualMousePosition()

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
end

function newgame:draw()
    love.graphics.clear(0.1, 0.1, 0.15, 1)

    display:Attach()

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setFont(self.titleFont)
    love.graphics.printf("Select Save Slot", 0, self.layout.title_y, self.virtual_width, "center")

    for i, slot in ipairs(self.slots) do
        local y = self.layout.slots_start_y + (i - 1) * self.layout.slot_spacing
        local is_selected = (i == self.selected or i == self.mouse_over)
        local is_hovered = (i == self.mouse_over)

        -- Draw slot box
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
            text_ui:draw("Slot " .. slot.slot .. " (Overwrite?)", self.virtual_width * 0.2, y, title_color, self.slotFont)

            text_ui:draw("HP: " .. slot.hp .. "/" .. slot.max_hp, self.virtual_width * 0.2, y + 24, {0.8, 0.8, 0.8, 1}, self.infoFont)
            text_ui:draw(slot.map_display or "Unknown", self.virtual_width * 0.2, y + 41, {0.8, 0.8, 0.8, 1}, self.infoFont)

            text_ui:draw(slot.time_string, self.virtual_width * 0.2, y + 58, {0.6, 0.6, 0.6, 1}, self.hintFont)
        else
            local new_color = is_selected and {0, 1, 0.5, 1} or {0.7, 0.7, 0.7, 1}
            text_ui:draw("Slot " .. slot.slot .. " - New Game", self.virtual_width * 0.2, y + 24, new_color, self.slotFont)
        end
    end

    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)

    if input:hasGamepad() then
        love.graphics.printf("D-Pad: Navigate | " ..
            input:getPrompt("menu_select") .. ": Start | " ..
            input:getPrompt("menu_back") .. ": Back",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("Keyboard: Arrow Keys / WASD | Enter: Start | ESC: Back | Mouse: Hover & Click",
            0, self.layout.hint_y, self.virtual_width, "center")
    else
        love.graphics.printf("Arrow Keys / WASD: Navigate | Enter: Start | ESC: Back",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("Mouse: Hover and Click",
            0, self.layout.hint_y, self.virtual_width, "center")
    end

    display:Detach()
end

function newgame:resize(w, h) display:Resize(w, h) end

function newgame:keypressed(key)
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
        local menu = require "game.scenes.menu"
        scene_control.switch("menu")
    end
end

function newgame:gamepadpressed(joystick, button)
    if input:wasPressed("menu_up", "gamepad", button) then
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.slots end
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.selected = self.selected + 1
        if self.selected > #self.slots then self.selected = 1 end
    elseif input:wasPressed("menu_select", "gamepad", button) then
        self:selectSlot(self.selected)
    elseif input:wasPressed("menu_back", "gamepad", button) then
        local menu = require "game.scenes.menu"
        scene_control.switch("menu")
    end
end

function newgame:selectSlot(slot_index)
    local slot = self.slots[slot_index]

    if slot.slot == "back" then
        local menu = require "game.scenes.menu"
        scene_control.switch("menu")
    else
        -- Start with level1 intro, passing slot info to intro scene
        local intro = require "game.scenes.intro"
        scene_control.switch("intro",
            "level1",
            constants.GAME_START.DEFAULT_MAP,
            constants.GAME_START.DEFAULT_SPAWN_X,
            constants.GAME_START.DEFAULT_SPAWN_Y,
            slot.slot)
    end
end

function newgame:mousepressed(x, y, button) end

function newgame:mousereleased(x, y, button)
    if button == 1 then
        if self.mouse_over > 0 then
            self.selected = self.mouse_over
            self:selectSlot(self.selected)
        end
    end
end

function newgame:touchpressed(id, x, y, dx, dy, pressure)
    local ui_scene = require "engine.ui.menu.helpers"
    self.mouse_over = ui_scene.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)
    return false
end

function newgame:touchreleased(id, x, y, dx, dy, pressure)
    local ui_scene = require "engine.ui.menu.helpers"
    local touched = ui_scene.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)
    if touched > 0 then
        self.selected = touched
        self:selectSlot(self.selected)
        return true
    end
    return false
end

return newgame

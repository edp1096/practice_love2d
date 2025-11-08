-- scenes/load/init.lua
-- Load game scene with save slot selection, delete confirmation, and gamepad support

local load = {}

local scene_control = require "engine.scene_control"
local display = require "engine.display"
local save_sys = require "engine.save"
local input = require "engine.input"
local fonts = require "engine.utils.fonts"

local slot_renderer = require "game.scenes.load.save_slot_renderer"
local input_handler = require "game.scenes.load.input"

function load:enter(previous, ...)
    self.previous = previous
    self.selected = 1

    -- Hide virtual gamepad in load menu
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    self.titleFont = fonts.title_large
    self.slotFont = fonts.option
    self.infoFont = fonts.info
    self.hintFont = fonts.info
    self.confirmFont = fonts.option

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

function load:exit()
    -- Cleanup if needed
end

function load:update(dt)
    if self.confirm_delete then
        -- Check Yes/No button hover
        local vmx, vmy = display:GetVirtualMousePosition()
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

    local vmx, vmy = display:GetVirtualMousePosition()

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

    display:Attach()

    love.graphics.setColor(1, 1, 1, 1)

    -- Draw title
    love.graphics.setFont(self.titleFont)
    love.graphics.printf("Load Game", 0, self.layout.title_y, self.virtual_width, "center")

    -- Draw all slots
    slot_renderer.drawAllSlots(self)

    -- Draw input hints
    slot_renderer.drawInputHints(self)

    -- Draw confirmation dialog if active
    if self.confirm_delete and self.delete_slot then
        slot_renderer.drawConfirmDialog(self)
    end

    display:Detach()
end

function load:resize(w, h)
    display:Resize(w, h)
end

function load:keypressed(key)
    input_handler.keypressed(self, key)
end

function load:gamepadpressed(joystick, button)
    input_handler.gamepadpressed(self, joystick, button)
end

function load:mousepressed(x, y, button)
    input_handler.mousepressed(self, x, y, button)
end

function load:mousereleased(x, y, button)
    input_handler.mousereleased(self, x, y, button)
end

function load:touchpressed(id, x, y, dx, dy, pressure)
    input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
end

function load:touchreleased(id, x, y, dx, dy, pressure)
    input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
end

return load

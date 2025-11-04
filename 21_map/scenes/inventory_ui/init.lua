-- scenes/inventory_ui/init.lua
-- Main inventory UI coordinator

local inventory_ui = {}

local screen = require "lib.screen"
local sound = require "systems.sound"
local slot_renderer = require "scenes.inventory_ui.slot_renderer"
local input_handler = require "scenes.inventory_ui.input"
local fonts = require "utils.fonts"

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

    self.title_font = fonts.option or love.graphics.getFont()
    self.item_font = fonts.info or love.graphics.getFont()
    self.desc_font = fonts.info or love.graphics.getFont()

    -- Close button settings
    self.close_button_size = 30
    self.close_button_padding = 15

    play_sound("ui", "open")
end

function inventory_ui:exit()
    play_sound("ui", "close")
end

function inventory_ui:update(dt)
    -- No gameplay update while in inventory
end

-- Delegate input handling to input module
function inventory_ui:keypressed(key)
    input_handler.keypressed(self, key)
end

function inventory_ui:gamepadpressed(joystick, button)
    input_handler.gamepadpressed(self, joystick, button)
end

function inventory_ui:gamepadaxis(joystick, axis, value)
    input_handler.gamepadaxis(self, joystick, axis, value)
end

function inventory_ui:mousepressed(x, y, button)
    input_handler.mousepressed(self, x, y, button)
end

function inventory_ui:touchpressed(id, x, y, dx, dy, pressure)
    return input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
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

    -- Draw close button (top-right corner)
    self.close_button_bounds = slot_renderer.renderCloseButton(
        window_x, window_y, window_w,
        self.close_button_size, self.close_button_padding
    )

    -- Draw close instruction
    love.graphics.setFont(self.desc_font)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.print("Press [I] or [ESC] to close", window_x + 20, window_y + 20)

    -- Draw items in grid
    slot_renderer.renderItemGrid(
        self.inventory, self.selected_slot,
        self.slot_size, self.slot_spacing,
        self.title_font, self.item_font, self.desc_font
    )

    -- Draw selected item details
    if #self.inventory.items > 0 then
        slot_renderer.renderItemDetails(
            self.inventory, self.selected_slot, self.player,
            window_x, self.slot_size, self.slot_spacing,
            self.item_font, self.desc_font
        )
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)

    screen:Detach()
end

return inventory_ui

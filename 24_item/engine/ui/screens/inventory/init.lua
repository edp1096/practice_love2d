-- engine/ui/screens/inventory/init.lua
-- Main inventory UI coordinator

local inventory = {}

local display = require "engine.core.display"
local sound = require "engine.core.sound"
local slot_renderer = require "engine.ui.screens.inventory.inventory_renderer"
local input_handler = require "engine.ui.screens.inventory.input"
local fonts = require "engine.utils.fonts"
local shapes = require "engine.utils.shapes"
local text_ui = require "engine.utils.text"
local input = require "engine.core.input"

-- Safe sound wrapper
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

function inventory:enter(previous, player_inventory, player)
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
    self.close_button_hovered = false  -- Track close button hover state

    play_sound("ui", "open")
end

function inventory:exit()
    play_sound("ui", "close")
end

function inventory:update(dt)
    -- Update close button hover state
    local coords = require "engine.core.coords"
    local mx, my = love.mouse.getPosition()
    local vmx, vmy = coords:physicalToVirtual(mx, my, display)

    self.close_button_hovered = false
    if self.close_button_bounds then
        local btn = self.close_button_bounds
        if vmx >= btn.x and vmx <= btn.x + btn.size and
           vmy >= btn.y and vmy <= btn.y + btn.size then
            self.close_button_hovered = true
        end
    end
end

-- Delegate input handling to input module
function inventory:keypressed(key)
    input_handler.keypressed(self, key)
end

function inventory:gamepadpressed(joystick, button)
    input_handler.gamepadpressed(self, joystick, button)
end

function inventory:gamepadaxis(joystick, axis, value)
    input_handler.gamepadaxis(self, joystick, axis, value)
end

function inventory:mousepressed(x, y, button)
    input_handler.mousepressed(self, x, y, button)
end

function inventory:touchpressed(id, x, y, dx, dy, pressure)
    return input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
end

function inventory:draw()
    -- Draw previous scene (dimmed)
    if self.previous_scene and self.previous_scene.draw then
        self.previous_scene:draw()
    end

    display:Attach()

    local vw, vh = display:GetVirtualDimensions()

    -- Draw dark overlay
    shapes:drawOverlay(vw, vh, 0.7)

    -- Draw window background
    local window_w = 600
    local window_h = 500
    local window_x = (vw - window_w) / 2
    local window_y = (vh - window_h) / 2

    shapes:drawPanel(window_x, window_y, window_w, window_h, {0.15, 0.15, 0.2, 0.95}, {0.3, 0.3, 0.4, 1}, 10)

    -- Draw title
    local title = "INVENTORY"
    local title_w = self.title_font:getWidth(title)
    text_ui:draw(title, (vw - title_w) / 2, window_y + 20, {1, 1, 1, 1}, self.title_font)

    -- Draw close button (top-right corner)
    self.close_button_bounds = slot_renderer.renderCloseButton(
        window_x, window_y, window_w,
        self.close_button_size, self.close_button_padding,
        self.close_button_hovered
    )

    -- Draw close instruction with dynamic input prompts
    local close_prompt1 = input:getPrompt("open_inventory") or "I"
    local close_prompt2 = input:getPrompt("menu_back") or "ESC"
    local close_text = string.format("Press %s or %s to close", close_prompt1, close_prompt2)
    text_ui:draw(close_text, window_x + 20, window_y + 20, {0.7, 0.7, 0.7, 1}, self.desc_font)

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

    display:Detach()
end

return inventory

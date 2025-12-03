-- engine/ui/screens/shop/init.lua
-- Shop UI overlay (refactored to use modular components)

local shop_ui = {}

local display = require "engine.core.display"
local sound = require "engine.core.sound"
local input = require "engine.core.input"
local ui_constants = require "engine.ui.constants"
local shop_system = require "engine.systems.shop"
local locale = require "engine.core.locale"

-- Import modular components
local state = require "engine.ui.screens.shop.state"
local shop_input = require "engine.ui.screens.shop.input"
local shop_render = require "engine.ui.screens.shop.render"

-- Safe sound wrapper
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

-- Overlay state
shop_ui.is_open = false

-- Open shop as overlay (called from gameplay)
function shop_ui:open(shop_id, inventory, level_system, item_registry)
    self.shop_id = shop_id
    self.inventory = inventory
    self.level_system = level_system
    self.item_registry = item_registry

    -- Get shop data
    self.shop_data = shop_system:getShop(shop_id)
    if not self.shop_data then
        print("[Shop] ERROR: Shop not found:", shop_id)
        return false
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

    -- Fonts (use locale system for Korean support)
    self.title_font = locale:getFont("option") or love.graphics.getFont()
    self.item_font = locale:getFont("info") or love.graphics.getFont()

    -- Close button
    self.close_button_size = ui_constants.CLOSE_BUTTON_SIZE
    self.close_button_padding = ui_constants.CLOSE_BUTTON_PADDING
    self.close_button_hovered = false

    -- Hover states
    self.hovered_item_index = nil
    self.hovered_qty_left = false
    self.hovered_qty_right = false
    self.hovered_qty_ok = false
    self.hovered_qty_cancel = false
    self.hovered_tab_buy = false
    self.hovered_tab_sell = false

    -- Joystick cooldown
    self.joystick_cooldown = 0
    self.joystick_repeat_delay = 0.15

    -- Quantity selection mode
    self.quantity_mode = false
    self.quantity = 1
    self.quantity_max = 1
    self.quantity_item = nil

    self.is_open = true
    play_sound("ui", "open")
    return true
end

-- Check if shop is open
function shop_ui:isOpen()
    return self.is_open
end

-- Legacy scene enter (for backwards compatibility)
function shop_ui:enter(previous, shop_id, inventory, level_system, item_registry)
    self.previous_scene = previous
    self:open(shop_id, inventory, level_system, item_registry)
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
    shop_input.handleGamepadInput(self, dt, play_sound)
end

function shop_ui:close()
    play_sound("ui", "close")

    -- Show virtual gamepad
    if input.virtual_gamepad then
        input.virtual_gamepad:show()
    end

    -- Overlay mode: just close
    if self.is_open then
        self.is_open = false
        return
    end

    -- Legacy scene mode: pop from stack
    local scene_control = require "engine.core.scene_control"
    scene_control.pop()
end

function shop_ui:draw()
    -- Only draw previous scene in legacy scene mode (not overlay)
    if not self.is_open and self.previous_scene and self.previous_scene.draw then
        self.previous_scene:draw()
    end

    display:Attach()
    shop_render.draw(self)
    display:Detach()
end

-- Input handlers (delegate to shop_input module)
function shop_ui:mousemoved(x, y)
    shop_input.mousemoved(self, x, y)
end

function shop_ui:mousepressed(x, y, button)
    shop_input.mousepressed(self, x, y, button, play_sound)
end

function shop_ui:wheelmoved(x, y)
    shop_input.wheelmoved(self, x, y, play_sound)
end

function shop_ui:keypressed(key)
    shop_input.keypressed(self, key, play_sound)
end

function shop_ui:gamepadpressed(joystick, button)
    shop_input.gamepadpressed(self, joystick, button, play_sound)
end

function shop_ui:touchpressed(id, x, y, dx, dy, pressure)
    shop_input.touchpressed(self, id, x, y, dx, dy, pressure, play_sound)
end

function shop_ui:touchmoved(id, x, y, dx, dy, pressure)
    shop_input.touchmoved(self, id, x, y, dx, dy, pressure)
end

function shop_ui:touchreleased(id, x, y, dx, dy, pressure)
    shop_input.touchreleased(self, id, x, y, dx, dy, pressure)
end

return shop_ui

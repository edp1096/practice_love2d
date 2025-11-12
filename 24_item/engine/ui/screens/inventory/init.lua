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

    -- Use item_id instead of slot index
    self.selected_item_id = self.inventory.selected_item_id

    -- Grid rendering (will be set during draw)
    self.grid_start_x = 0
    self.grid_start_y = 0

    self.title_font = fonts.option or love.graphics.getFont()
    self.item_font = fonts.info or love.graphics.getFont()
    self.desc_font = fonts.info or love.graphics.getFont()

    -- Close button settings
    self.close_button_size = 30
    self.close_button_padding = 15
    self.close_button_hovered = false  -- Track close button hover state

    -- Drag and drop state
    self.drag_state = {
        active = false,
        item_id = nil,
        item_obj = nil,  -- Store item object reference while dragging
        offset_x = 0,  -- Mouse offset from item top-left
        offset_y = 0,
        origin_x = 0,  -- Original position (for cancel)
        origin_y = 0,
        origin_width = 0,
        origin_height = 0,
        origin_rotated = false,
        visual_x = 0,  -- Current visual position (screen coords)
        visual_y = 0
    }

    -- Gamepad cursor state
    self.cursor_mode = false  -- false = mouse, true = gamepad cursor
    self.cursor_x = 1  -- Grid X position (1-10)
    self.cursor_y = 1  -- Grid Y position (1-6)

    -- Joystick state (for analog stick movement with cooldown)
    self.joystick_cooldown = 0  -- Time until next joystick move
    self.joystick_repeat_delay = 0.15  -- Seconds between moves

    -- Gamepad drag state (separate from mouse drag)
    self.gamepad_drag = {
        active = false,
        item_id = nil,
        item_obj = nil,
        origin_x = 0,
        origin_y = 0,
        origin_width = 0,
        origin_height = 0,
        origin_rotated = false
    }

    play_sound("ui", "open")
end

function inventory:exit()
    play_sound("ui", "close")
end

function inventory:update(dt)
    local coords = require "engine.core.coords"
    local mx, my = love.mouse.getPosition()
    local vmx, vmy = coords:physicalToVirtual(mx, my, display)

    -- Update close button hover state
    self.close_button_hovered = false
    if self.close_button_bounds then
        local btn = self.close_button_bounds
        if vmx >= btn.x and vmx <= btn.x + btn.size and
           vmy >= btn.y and vmy <= btn.y + btn.size then
            self.close_button_hovered = true
        end
    end

    -- Update drag state (follow mouse)
    if self.drag_state.active then
        self.drag_state.visual_x = vmx
        self.drag_state.visual_y = vmy
    end

    -- Update joystick cooldown
    if self.joystick_cooldown > 0 then
        self.joystick_cooldown = self.joystick_cooldown - dt
    end

    -- Check joystick input for cursor movement
    local joysticks = love.joystick.getJoysticks()
    if #joysticks > 0 and self.joystick_cooldown <= 0 then
        local joystick = joysticks[1]
        local threshold = 0.5
        local lx = joystick:getGamepadAxis("leftx")
        local ly = joystick:getGamepadAxis("lefty")

        if math.abs(lx) > threshold or math.abs(ly) > threshold then
            self.cursor_mode = true

            -- Determine primary direction (move 1 step at a time, wrap around at edges)
            if math.abs(lx) > math.abs(ly) then
                if lx > threshold then
                    self.cursor_x = self.cursor_x == self.inventory.grid_width and 1 or self.cursor_x + 1
                    self.joystick_cooldown = self.joystick_repeat_delay
                    play_sound("ui", "move")
                elseif lx < -threshold then
                    self.cursor_x = self.cursor_x == 1 and self.inventory.grid_width or self.cursor_x - 1
                    self.joystick_cooldown = self.joystick_repeat_delay
                    play_sound("ui", "move")
                end
            else
                if ly > threshold then
                    self.cursor_y = self.cursor_y == self.inventory.grid_height and 1 or self.cursor_y + 1
                    self.joystick_cooldown = self.joystick_repeat_delay
                    play_sound("ui", "move")
                elseif ly < -threshold then
                    self.cursor_y = self.cursor_y == 1 and self.inventory.grid_height or self.cursor_y - 1
                    self.joystick_cooldown = self.joystick_repeat_delay
                    play_sound("ui", "move")
                end
            end
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

function inventory:mousereleased(x, y, button)
    input_handler.mousereleased(self, x, y, button)
end

function inventory:mousemoved(x, y, dx, dy)
    input_handler.mousemoved(self, x, y, dx, dy)
end

function inventory:touchpressed(id, x, y, dx, dy, pressure)
    return input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
end

function inventory:touchreleased(id, x, y, dx, dy, pressure)
    return input_handler.touchreleased(self, id, x, y, dx, dy, pressure)
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

    -- Draw window background (wider to fit equipment slots + grid)
    local window_w = 750  -- Increased from 600 to fit equipment + grid
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

    -- Draw usage instruction (if item selected)
    if self.selected_item_id then
        local use_prompt = input:getPrompt("use_item") or input:getPrompt("menu_select") or "ENTER"
        local use_text = string.format("Press %s to use", use_prompt)
        text_ui:draw(use_text, window_x + 20, window_y + 38, {0.6, 0.8, 1, 1}, self.desc_font)
    end

    -- Draw equipment slots panel (left side)
    self.equipment_bounds = slot_renderer.renderEquipmentSlots(
        self.inventory, window_x, window_y,
        self.title_font, self.item_font, self.desc_font
    )

    -- Draw items in grid (returns grid start position)
    self.grid_start_x, self.grid_start_y = slot_renderer.renderItemGrid(
        self.inventory, self.selected_item_id,
        self.title_font, self.item_font, self.desc_font,
        self.drag_state,  -- Pass drag state for rendering dragged item
        window_x,  -- Pass window_x for layout positioning
        window_y,  -- Pass window_y for relative positioning
        self.cursor_mode,  -- Pass cursor mode
        self.cursor_x,  -- Pass cursor X position
        self.cursor_y,  -- Pass cursor Y position
        self.gamepad_drag  -- Pass gamepad drag state
    )

    -- Draw selected item details
    slot_renderer.renderItemDetails(
        self.inventory, self.selected_item_id, self.player,
        window_x, window_y, self.grid_start_y,
        self.item_font, self.desc_font
    )

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)

    display:Detach()
end

return inventory

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
local colors = require "engine.ui.colors"

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

    -- Hide virtual gamepad when inventory is open (mobile)
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    -- Use item_id instead of slot index
    self.selected_item_id = self.inventory.selected_item_id

    -- Grid rendering (will be set during draw)
    self.grid_start_x = 0
    self.grid_start_y = 0

    self.title_font = love.graphics.newFont(16)  -- Match questlog title size (was fonts.option = 22)
    self.item_font = fonts.info or love.graphics.getFont()  -- 14
    self.desc_font = fonts.info or love.graphics.getFont()  -- 14

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
        visual_y = 0,
        from_quickslot_index = nil  -- Track if dragged from quickslot
    }

    -- Gamepad cursor state
    self.cursor_mode = false  -- false = mouse, true = gamepad cursor
    self.cursor_x = 1  -- Grid X position (1-10)
    self.cursor_y = 1  -- Grid Y position (1-6)

    -- Quickslot hold-to-remove state
    self.quickslot_hold = {
        active = false,
        slot_index = nil,
        timer = 0,
        duration = 0.5,  -- 0.5 seconds to remove
        source = nil  -- "mouse" or "gamepad"
    }

    -- Equipment slot cursor state
    self.equipment_mode = false  -- true when cursor is on equipment slots
    self.equipment_cursor_x = 0  -- Equipment slot X (0 or 1)
    self.equipment_cursor_y = 0  -- Equipment slot Y (0, 1, 2, or 3)

    -- Quickslot cursor state
    self.quickslot_mode = false  -- true when cursor is on quickslots
    self.quickslot_cursor = 1    -- Which quickslot is selected (1-5)

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

    -- Show virtual gamepad when inventory closes (mobile)
    if input.virtual_gamepad then
        input.virtual_gamepad:show()
    end
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

    -- Update quickslot hold-to-remove timer
    if self.quickslot_hold.active then
        self.quickslot_hold.timer = self.quickslot_hold.timer + dt
        -- Auto-cap at duration (no need to go higher)
        if self.quickslot_hold.timer > self.quickslot_hold.duration then
            self.quickslot_hold.timer = self.quickslot_hold.duration
        end

        -- Check if X button (parry) is released (for gamepad hold-to-remove)
        -- Only check gamepad if the hold was started by gamepad
        if self.quickslot_hold.source == "gamepad" then
            local joysticks = love.joystick.getJoysticks()
            if #joysticks > 0 then
                local joystick = joysticks[1]
                -- Check if X button is no longer held down
                if not joystick:isGamepadDown("x") then
                    -- Button released, check if hold duration was met
                    if self.quickslot_hold.timer >= self.quickslot_hold.duration then
                        -- Hold duration reached, remove item from quickslot
                        local slot_index = self.quickslot_hold.slot_index
                        if slot_index and self.inventory.quickslots[slot_index] then
                            self.inventory:removeQuickslot(slot_index)
                            play_sound("ui", "select")
                        end
                    end

                    -- Reset hold state
                    self.quickslot_hold.active = false
                    self.quickslot_hold.slot_index = nil
                    self.quickslot_hold.timer = 0
                    self.quickslot_hold.source = nil
                end
            end
        end
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

            -- Determine primary direction (move 1 step at a time)
            if math.abs(lx) > math.abs(ly) then
                if lx > threshold then
                    -- Move right
                    if self.quickslot_mode then
                        -- Move right in quickslots (wrap around)
                        self.quickslot_cursor = self.quickslot_cursor == 5 and 1 or self.quickslot_cursor + 1
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    elseif self.equipment_mode then
                        -- Switch from equipment to grid
                        self.equipment_mode = false
                        self.cursor_x = 1
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    else
                        -- Move right in grid (wrap around)
                        self.cursor_x = self.cursor_x == self.inventory.grid_width and 1 or self.cursor_x + 1
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    end
                elseif lx < -threshold then
                    -- Move left
                    if self.quickslot_mode then
                        -- Move left in quickslots (wrap around)
                        self.quickslot_cursor = self.quickslot_cursor == 1 and 5 or self.quickslot_cursor - 1
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    elseif self.equipment_mode then
                        -- Toggle equipment X (wrap around: 0 <-> 1)
                        self.equipment_cursor_x = (self.equipment_cursor_x == 0) and 1 or 0
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    else
                        if self.cursor_x == 1 then
                            -- Switch from grid to equipment
                            self.equipment_mode = true
                            self.equipment_cursor_x = 1
                            self.joystick_cooldown = self.joystick_repeat_delay
                            play_sound("ui", "move")
                        else
                            -- Move left in grid (wrap around)
                            self.cursor_x = self.cursor_x - 1
                            self.joystick_cooldown = self.joystick_repeat_delay
                            play_sound("ui", "move")
                        end
                    end
                end
            else
                if ly > threshold then
                    -- Move down
                    if self.quickslot_mode then
                        -- In quickslot mode, down does nothing (or could wrap to grid top)
                        -- Do nothing for now
                    elseif self.equipment_mode then
                        self.equipment_cursor_y = (self.equipment_cursor_y + 1) % 4
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    else
                        -- In grid mode
                        if self.cursor_y == self.inventory.grid_height then
                            -- At bottom of grid, enter quickslot mode
                            self.quickslot_mode = true
                            self.joystick_cooldown = self.joystick_repeat_delay
                            play_sound("ui", "move")
                        else
                            -- Move down in grid
                            self.cursor_y = self.cursor_y + 1
                            self.joystick_cooldown = self.joystick_repeat_delay
                            play_sound("ui", "move")
                        end
                    end
                elseif ly < -threshold then
                    -- Move up
                    if self.quickslot_mode then
                        -- Exit quickslot mode, return to grid bottom
                        self.quickslot_mode = false
                        self.cursor_y = self.inventory.grid_height
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    elseif self.equipment_mode then
                        self.equipment_cursor_y = (self.equipment_cursor_y - 1 + 4) % 4
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    else
                        self.cursor_y = self.cursor_y == 1 and self.inventory.grid_height or self.cursor_y - 1
                        self.joystick_cooldown = self.joystick_repeat_delay
                        play_sound("ui", "move")
                    end
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
    -- Check if we're inside a container
    local in_container = self.previous_scene and self.previous_scene.current_tab

    -- Only draw background if NOT in container
    if not in_container then
        -- Draw previous scene (dimmed)
        if self.previous_scene and self.previous_scene.draw then
            self.previous_scene:draw()
        end

        display:Attach()

        local vw, vh = display:GetVirtualDimensions()

        -- Draw dark overlay
        shapes:drawOverlay(vw, vh, 0.7)
    end

    local vw, vh = display:GetVirtualDimensions()

    -- Draw window background (wider to fit equipment slots + grid + quickslots)
    local window_w = 720  -- Proper width for balanced margins (20 + 130 + 30 + 590 + 20)
    local window_h = 450  -- Reduced from 500 for 5-row grid (one row removed)
    local window_x = (vw - window_w) / 2
    local window_y = in_container and 70 or (vh - window_h) / 2  -- Higher position in container (tab bar at 20, tab height 30, margin 20)

    shapes:drawPanel(window_x, window_y, window_w, window_h, colors.for_inventory_bg, colors.for_inventory_border, 10)

    -- Draw title
    local title = "INVENTORY"
    local title_w = self.title_font:getWidth(title)
    text_ui:draw(title, (vw - title_w) / 2, window_y + 20, {1, 1, 1, 1}, self.title_font)

    -- Draw close button and instructions (only if NOT in container)
    if not in_container then
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
        text_ui:draw(close_text, window_x + 20, window_y + 20, colors.for_text_mid_gray, self.desc_font)
    end

    -- Draw usage instruction (if item selected)
    if self.selected_item_id then
        local use_prompt = input:getPrompt("use_item") or input:getPrompt("menu_select") or "ENTER"
        local use_text = string.format("Press %s to use", use_prompt)
        text_ui:draw(use_text, window_x + 20, window_y + 38, {0.6, 0.8, 1, 1}, self.desc_font)
    end

    -- Draw equipment slots panel (left side)
    self.equipment_bounds = slot_renderer.renderEquipmentSlots(
        self.inventory, window_x, window_y,
        self.title_font, self.item_font, self.desc_font,
        self.equipment_mode,  -- Pass equipment mode
        self.equipment_cursor_x,  -- Pass equipment cursor X
        self.equipment_cursor_y,  -- Pass equipment cursor Y
        self.drag_state  -- Pass drag state for highlighting droppable slots
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

    -- Draw quickslots at bottom of inventory
    self.quickslot_bounds = slot_renderer.renderQuickslots(
        self.inventory, window_x, window_y, window_w, window_h,
        self.player, self.drag_state, self.quickslot_hold,
        self.quickslot_mode, self.quickslot_cursor
    )

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)

    -- Only detach if NOT in container
    if not in_container then
        display:Detach()
    end
end

return inventory

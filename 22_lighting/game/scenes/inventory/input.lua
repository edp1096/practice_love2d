-- scenes/inventory/input.lua
-- Handles all input for the inventory UI

local input_handler = {}

local screen = require "engine.display"
local input = require "engine.input"
local sound = require "engine.sound"
local coords = require "engine.coords"

-- Safe sound wrapper
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

-- Handle keyboard input
function input_handler.keypressed(self, key)
    if key == "i" or key == "escape" or input:wasPressed("pause", "keyboard", key) then
        -- I key or ESC to close (toggle behavior)
        local scene_control = require "engine.scene_control"
        scene_control.pop()
    elseif key == "left" or key == "a" then
        input_handler.moveSelection(self, -1)
    elseif key == "right" or key == "d" then
        input_handler.moveSelection(self, 1)
    elseif key == "return" or key == "space" or key == "e" then
        input_handler.useSelectedItem(self)
    elseif key == "q" then
        input_handler.useSelectedItem(self)
    elseif tonumber(key) then
        local slot_num = tonumber(key)
        if slot_num >= 1 and slot_num <= #self.inventory.items then
            self.selected_slot = slot_num
            self.inventory.selected_slot = slot_num
            play_sound("ui", "select")
        end
    end
end

-- Handle gamepad input
function input_handler.gamepadpressed(self, joystick, button)
    if button == "b" or button == "start" then
        -- B button or Start to close inventory
        local scene_control = require "engine.scene_control"
        scene_control.pop()
    elseif button == "righttrigger" then
        -- R2 to close inventory (toggle behavior)
        local scene_control = require "engine.scene_control"
        scene_control.pop()
    elseif button == "dpleft" then
        input_handler.moveSelection(self, -1)
    elseif button == "dpright" then
        input_handler.moveSelection(self, 1)
    elseif button == "a" or button == "x" then
        input_handler.useSelectedItem(self)
    elseif button == "leftshoulder" then
        -- L1 to use item
        input_handler.useSelectedItem(self)
    end
end

-- Handle gamepad axis (for Xbox controller triggers)
function input_handler.gamepadaxis(self, joystick, axis, value)
    -- Use input coordinator to handle trigger-to-button conversion
    local input_sys = require "engine.input"
    local action = input_sys:handleGamepadAxis(joystick, axis, value)

    if action == "open_inventory" then
        -- RT trigger pressed - close inventory (toggle behavior)
        local scene_control = require "engine.scene_control"
        scene_control.pop()
    elseif action == "next_item" then
        -- LT trigger pressed - move selection
        input_handler.moveSelection(self, 1)
    end
end

-- Handle mouse input
function input_handler.mousepressed(self, x, y, button)
    if button == 1 then
        input_handler.handleClick(self, x, y)
    elseif button == 2 then
        -- Right click to use item
        input_handler.useSelectedItem(self)
    end
end

-- Handle touch input
function input_handler.touchpressed(self, id, x, y, dx, dy, pressure)
    -- Check if touch is in virtual gamepad area FIRST (let it handle R2)
    local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")
    if is_mobile then
        local virtual_gamepad = require "engine.input.virtual_gamepad"
        if virtual_gamepad and virtual_gamepad:isInVirtualPadArea(x, y) then
            -- Let virtual gamepad handle it (R2 button, etc.)
            -- Return false immediately without processing the touch
            return false
        end
    end

    -- Convert to virtual coords for UI check using coords module
    local vx, vy = coords:physicalToVirtual(x, y, screen)

    -- Only handle touch if it's in the UI area (not gamepad area)
    -- Handle touch as mouse click for inventory UI
    input_handler.handleClick(self, x, y)
    -- Block other handlers
    return true
end

-- Handle click/touch on UI elements
function input_handler.handleClick(self, x, y)
    -- Convert screen coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, screen)

    -- Check if clicked on close button
    if self.close_button_bounds then
        local cb = self.close_button_bounds
        if vx >= cb.x and vx <= cb.x + cb.size and
            vy >= cb.y and vy <= cb.y + cb.size then
            local scene_control = require "engine.scene_control"
            scene_control.pop()
            return
        end
    end

    -- Get virtual dimensions for slot calculation
    local vw, vh = screen:GetVirtualDimensions()

    -- Check if clicked on a slot
    local start_x = (vw - (self.slot_size + self.slot_spacing) * math.min(#self.inventory.items, 5)) / 2
    local start_y = 150

    for i, item in ipairs(self.inventory.items) do
        local row = math.floor((i - 1) / 5)
        local col = (i - 1) % 5
        local slot_x = start_x + col * (self.slot_size + self.slot_spacing)
        local slot_y = start_y + row * (self.slot_size + self.slot_spacing)

        if vx >= slot_x and vx <= slot_x + self.slot_size and
            vy >= slot_y and vy <= slot_y + self.slot_size then
            self.selected_slot = i
            self.inventory.selected_slot = i
            play_sound("ui", "select")
            break
        end
    end
end

-- Move selection up or down
function input_handler.moveSelection(self, direction)
    if #self.inventory.items == 0 then return end

    self.selected_slot = self.selected_slot + direction
    if self.selected_slot < 1 then
        self.selected_slot = #self.inventory.items
    elseif self.selected_slot > #self.inventory.items then
        self.selected_slot = 1
    end

    self.inventory.selected_slot = self.selected_slot
    play_sound("ui", "select")
end

-- Use the currently selected item
function input_handler.useSelectedItem(self)
    if self.inventory:useSelectedItem(self.player) then
        play_sound("ui", "use")

        -- Update selected slot if item was consumed
        if self.selected_slot > #self.inventory.items and self.selected_slot > 1 then
            self.selected_slot = #self.inventory.items
            self.inventory.selected_slot = self.selected_slot
        end
    else
        play_sound("ui", "error")
    end
end

return input_handler

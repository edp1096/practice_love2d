-- engine/ui/screens/inventory/input.lua
-- Handles all input for the inventory UI

local input_handler = {}

local display = require "engine.core.display"
local input = require "engine.core.input"
local sound = require "engine.core.sound"
local coords = require "engine.core.coords"

-- Constants
local SLOTS_PER_ROW = 5

-- Safe sound wrapper
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end

-- Handle keyboard input
function input_handler.keypressed(self, key)
    -- Handle debug keys first
    local debug = require "engine.core.debug"
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process inventory keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if input:wasPressed("open_inventory", "keyboard", key) or input:wasPressed("menu_back", "keyboard", key) or input:wasPressed("pause", "keyboard", key) then
        -- I key, menu_back, or pause to close (toggle behavior)
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif input:wasPressed("menu_left", "keyboard", key) then
        input_handler.moveSelection(self, -1)
    elseif input:wasPressed("menu_right", "keyboard", key) then
        input_handler.moveSelection(self, 1)
    elseif input:wasPressed("menu_select", "keyboard", key) then
        input_handler.useSelectedItem(self)
    elseif input:wasPressed("use_item", "keyboard", key) then
        -- Use item (Q key by default, configurable via input_config)
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
    if input:wasPressed("menu_back", "gamepad", button) or input:wasPressed("pause", "gamepad", button) then
        -- B button or Start to close inventory
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif input:wasPressed("open_inventory", "gamepad", button) then
        -- "open_inventory" action to close inventory (toggle behavior)
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif input:wasPressed("menu_left", "gamepad", button) then
        input_handler.moveSelection(self, -1)
    elseif input:wasPressed("menu_right", "gamepad", button) then
        input_handler.moveSelection(self, 1)
    elseif input:wasPressed("menu_select", "gamepad", button) then
        input_handler.useSelectedItem(self)
    elseif input:wasPressed("use_item", "gamepad", button) then
        -- "use_item" action (configurable via input_config)
        input_handler.useSelectedItem(self)
    end
end

-- Handle gamepad axis (for Xbox controller triggers)
function input_handler.gamepadaxis(self, joystick, axis, value)
    -- Use input coordinator to handle trigger-to-button conversion
    local input_sys = require "engine.core.input"
    local action = input_sys:handleGamepadAxis(joystick, axis, value)

    if action == "open_inventory" then
        -- "open_inventory" trigger pressed - close inventory (toggle behavior)
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif action == "next_item" then
        -- "next_item" trigger pressed - move selection
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
    -- Check if touch is in virtual gamepad area FIRST
    local is_mobile = (love.system.getOS() == "Android" or love.system.getOS() == "iOS")
    if is_mobile then
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        if virtual_gamepad and virtual_gamepad:isInVirtualPadArea(x, y) then
            -- Let virtual gamepad handle it
            -- Return false immediately without processing the touch
            return false
        end
    end

    -- Convert to virtual coords for UI check using coords module
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Only handle touch if it's in the UI area (not gamepad area)
    -- Handle touch as mouse click for inventory UI
    input_handler.handleClick(self, x, y)
    -- Block other handlers
    return true
end

-- Handle click/touch on UI elements
function input_handler.handleClick(self, x, y)
    -- Convert screen coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, display)

    -- Check if clicked on close button
    if self.close_button_bounds then
        local cb = self.close_button_bounds
        if vx >= cb.x and vx <= cb.x + cb.size and
            vy >= cb.y and vy <= cb.y + cb.size then
            local scene_control = require "engine.core.scene_control"
            scene_control.pop()
            return
        end
    end

    -- Get virtual dimensions for slot calculation
    local vw, vh = display:GetVirtualDimensions()

    -- Check if clicked on a slot
    local start_x = (vw - (self.slot_size + self.slot_spacing) * math.min(#self.inventory.items, SLOTS_PER_ROW)) / 2
    local start_y = 150

    for i, item in ipairs(self.inventory.items) do
        local row = math.floor((i - 1) / SLOTS_PER_ROW)
        local col = (i - 1) % SLOTS_PER_ROW
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

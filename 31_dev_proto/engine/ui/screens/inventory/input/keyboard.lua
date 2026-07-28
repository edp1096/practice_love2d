-- engine/ui/screens/inventory/input/keyboard.lua
-- Keyboard input handling for inventory

local keyboard_input = {}

local input = require "engine.core.input"
local debug = require "engine.core.debug"

-- Handle keyboard input
function keyboard_input.keypressed(self, key, helpers)
    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process inventory keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if input:wasPressed("open_inventory", "keyboard", key) or input:wasPressed("menu_back", "keyboard", key) or input:wasPressed("pause", "keyboard", key) then
        -- I key, menu_back, or pause to close (toggle behavior)
        local scene_control = require "engine.core.scene_control"
        scene_control.pop()
    elseif input:wasPressed("menu_left", "keyboard", key) or input:wasPressed("menu_right", "keyboard", key) then
        -- Navigate between items
        helpers.moveSelection(self)
    elseif input:wasPressed("menu_select", "keyboard", key) then
        helpers.useSelectedItem(self)
    elseif input:wasPressed("use_item", "keyboard", key) then
        -- Use item (Q key by default, configurable via input_config)
        helpers.useSelectedItem(self)
    elseif tonumber(key) then
        local slot_num = tonumber(key)
        -- Number keys 1-9: quick select items by grid position
        helpers.selectItemByNumber(self, slot_num)
    end
end

return keyboard_input

-- engine/ui/screens/load/input.lua
-- Input handling for load scene

local input_handler = {}

local scene_control = require "engine.core.scene_control"
local save_sys = require "engine.core.save"
local input = require "engine.core.input"
local debug = require "engine.core.debug"
local coords = require "engine.core.coords"
local display = require "engine.core.display"

-- Select a slot (load game or go back)
function input_handler.selectSlot(load_scene, slot_index)
    local slot = load_scene.slots[slot_index]

    if slot.slot == "back" then
        scene_control.switch("menu")
    elseif slot.exists then
        scene_control.switch("gameplay", slot.map, slot.x, slot.y, slot.slot, false)  -- is_new_game = false
    end
end

-- Delete slot after confirmation
local function performDelete(load_scene)
    save_sys:deleteSlot(load_scene.delete_slot)
    load_scene.slots = save_sys:getAllSlotsInfo()
    table.insert(load_scene.slots, {
        exists = false,
        slot = "back",
        display_name = "Back to Menu"
    })
    load_scene.confirm_delete = false
    load_scene.delete_slot = nil
    load_scene.confirm_selected = 1
end

-- Cancel delete confirmation
local function cancelDelete(load_scene)
    load_scene.confirm_delete = false
    load_scene.delete_slot = nil
    load_scene.confirm_selected = 1
end

-- Keyboard input
function input_handler.keypressed(load_scene, key)
    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process load keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if load_scene.confirm_delete then
        -- Delete confirmation dialog
        if input:wasPressed("menu_left", "keyboard", key) then
            load_scene.confirm_selected = 1 -- No
        elseif input:wasPressed("menu_right", "keyboard", key) then
            load_scene.confirm_selected = 2 -- Yes
        elseif input:wasPressed("menu_select", "keyboard", key) then
            if load_scene.confirm_selected == 2 then
                performDelete(load_scene)
            else
                cancelDelete(load_scene)
            end
        elseif input:wasPressed("menu_back", "keyboard", key) then
            cancelDelete(load_scene)
        end
        return
    end

    -- Normal navigation
    if input:wasPressed("menu_up", "keyboard", key) then
        load_scene.selected = load_scene.selected - 1
        if load_scene.selected < 1 then
            load_scene.selected = #load_scene.slots
        end
    elseif input:wasPressed("menu_down", "keyboard", key) then
        load_scene.selected = load_scene.selected + 1
        if load_scene.selected > #load_scene.slots then
            load_scene.selected = 1
        end
    elseif input:wasPressed("menu_select", "keyboard", key) then
        input_handler.selectSlot(load_scene, load_scene.selected)
    elseif input:wasPressed("menu_back", "keyboard", key) then
        scene_control.switch("menu")
    elseif input:wasPressed("delete_item", "keyboard", key) then
        -- Delete key for save slots
        local slot = load_scene.slots[load_scene.selected]
        if slot and slot.exists and slot.slot ~= "back" then
            load_scene.confirm_delete = true
            load_scene.delete_slot = slot.slot
            load_scene.confirm_selected = 1 -- Default to No
        end
    end
end

-- Gamepad input
function input_handler.gamepadpressed(load_scene, joystick, button)
    if load_scene.confirm_delete then
        -- Delete confirmation dialog
        if input:wasPressed("menu_left", "gamepad", button) then
            load_scene.confirm_selected = 1 -- No
        elseif input:wasPressed("menu_right", "gamepad", button) then
            load_scene.confirm_selected = 2 -- Yes
        elseif input:wasPressed("menu_select", "gamepad", button) then
            if load_scene.confirm_selected == 2 then
                performDelete(load_scene)
            else
                cancelDelete(load_scene)
            end
        elseif input:wasPressed("menu_back", "gamepad", button) then
            cancelDelete(load_scene)
        end
        return
    end

    -- Normal navigation
    if input:wasPressed("menu_up", "gamepad", button) then
        load_scene.selected = load_scene.selected - 1
        if load_scene.selected < 1 then
            load_scene.selected = #load_scene.slots
        end
    elseif input:wasPressed("menu_down", "gamepad", button) then
        load_scene.selected = load_scene.selected + 1
        if load_scene.selected > #load_scene.slots then
            load_scene.selected = 1
        end
    elseif input:wasPressed("menu_select", "gamepad", button) then
        input_handler.selectSlot(load_scene, load_scene.selected)
    elseif input:wasPressed("menu_back", "gamepad", button) then
        scene_control.switch("menu")
    elseif input:wasPressed("interact", "gamepad", button) then
        -- Y button - delete selected slot (if exists)
        local slot = load_scene.slots[load_scene.selected]
        if slot and slot.exists and slot.slot ~= "back" then
            load_scene.confirm_delete = true
            load_scene.delete_slot = slot.slot
            load_scene.confirm_selected = 1 -- Default to No
        end
    end
end

-- Mouse pressed (no action needed)
function input_handler.mousepressed(load_scene, x, y, button)
    -- Empty implementation - all mouse handling in mousereleased
end

-- Mouse released
function input_handler.mousereleased(load_scene, x, y, button)
    if button ~= 1 then return end

    if load_scene.confirm_delete then
        -- Check Yes/No button clicks
        if load_scene.confirm_mouse_over == 1 then
            cancelDelete(load_scene)
        elseif load_scene.confirm_mouse_over == 2 then
            performDelete(load_scene)
        end
        return
    end

    -- Check if X button was clicked
    if load_scene.mouse_over_delete > 0 then
        local slot = load_scene.slots[load_scene.mouse_over_delete]
        if slot and slot.exists and slot.slot ~= "back" then
            load_scene.confirm_delete = true
            load_scene.delete_slot = slot.slot
            load_scene.confirm_selected = 1 -- Default to No
        end
    -- Normal slot click
    elseif load_scene.mouse_over > 0 then
        load_scene.selected = load_scene.mouse_over
        input_handler.selectSlot(load_scene, load_scene.selected)
    end
end

-- Touch pressed
function input_handler.touchpressed(load_scene, id, x, y, dx, dy, pressure)
    -- Convert physical touch to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, display)

    input_handler.mousepressed(load_scene, vx, vy, 1)
    return false
end

-- Touch released
function input_handler.touchreleased(load_scene, id, x, y, dx, dy, pressure)
    -- Convert physical touch to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, display)

    input_handler.mousereleased(load_scene, vx, vy, 1)
    return true
end

return input_handler

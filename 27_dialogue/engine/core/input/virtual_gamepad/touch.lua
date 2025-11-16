-- engine/core/input/virtual_gamepad/touch.lua
-- Touch handling logic for virtual gamepad

local coords = require "engine.core.coords"

local touch = {}

-- Main touch press handler
function touch.handlePress(id, x, y, vgp)
    if not vgp.enabled then return false end
    if not vgp.visible then return false end

    -- Convert physical touch coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, vgp.display)

    vgp.touches[id] = { x = vx, y = vy, start_x = vx, start_y = vy }

    -- Check D-pad (movement)
    if touch.isInDPad(vx, vy, vgp) then
        vgp.touches[id].type = "dpad"
        touch.updateDPad(vx, vy, vgp)
        -- Deactivate aim when touching D-pad
        touch.resetAimStick(vgp)
        return true
    end

    -- Check action buttons
    for name, button in pairs(vgp.buttons) do
        if touch.isInButton(vx, vy, button, vgp) then
            button.pressed = true
            vgp.touches[id].type = "button"
            vgp.touches[id].button = name
            touch.triggerButtonPress(name, vgp)
            -- Deactivate aim when pressing buttons
            touch.resetAimStick(vgp)
            return true
        end
    end

    -- Check menu button
    if touch.isInButton(vx, vy, vgp.menu_button, vgp) then
        vgp.menu_button.pressed = true
        vgp.touches[id].type = "menu"
        touch.triggerMenuPress(vgp)
        -- Deactivate aim when pressing menu
        touch.resetAimStick(vgp)
        return true
    end

    -- Check aim stick
    if touch.isInAimStick(vx, vy, vgp) then
        vgp.touches[id].type = "aim_stick"
        vgp.aim_stick.active = true
        vgp.aim_stick.touch_id = id
        touch.updateAimStick(vx, vy, vgp)
        return true
    end

    -- No control was touched
    return false
end

-- Main touch release handler
function touch.handleRelease(id, x, y, vgp)
    if not vgp.enabled then return false end
    if not vgp.visible then return false end

    local touch_data = vgp.touches[id]
    if not touch_data then return false end

    if touch_data.type == "dpad" then
        touch.resetDPad(vgp)
        vgp.touches[id] = nil
        vgp.mouse_aim_block_time = vgp.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch_data.type == "button" then
        local button = vgp.buttons[touch_data.button]
        if button then
            button.pressed = false
            touch.triggerButtonRelease(touch_data.button, vgp)
        end
        vgp.touches[id] = nil
        vgp.mouse_aim_block_time = vgp.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch_data.type == "menu" then
        vgp.menu_button.pressed = false
        vgp.touches[id] = nil
        vgp.mouse_aim_block_time = vgp.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch_data.type == "aim_stick" then
        if vgp.aim_stick.touch_id == id then
            touch.resetAimStick(vgp)
        end
        vgp.touches[id] = nil
        vgp.mouse_aim_block_time = vgp.MOUSE_AIM_BLOCK_DURATION
        return true
    end

    vgp.touches[id] = nil
    return false
end

-- Main touch move handler
function touch.handleMove(id, x, y, vgp)
    if not vgp.enabled then return false end
    if not vgp.visible then return false end

    local touch_data = vgp.touches[id]
    if not touch_data then return false end

    -- Convert physical touch coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, vgp.display)

    touch_data.x = vx
    touch_data.y = vy

    if touch_data.type == "dpad" then
        touch.updateDPad(vx, vy, vgp)
        return true
    elseif touch_data.type == "aim_stick" then
        touch.updateAimStick(vx, vy, vgp)
        return true
    end

    return false
end

-- Check if coordinates are in D-pad
function touch.isInDPad(x, y, vgp)
    local dx = x - vgp.dpad.x
    local dy = y - vgp.dpad.y
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist <= vgp.dpad.radius
end

-- Check if touch is in aim stick area
function touch.isInAimStick(x, y, vgp)
    local dx = x - vgp.aim_stick.x
    local dy = y - vgp.aim_stick.y
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist <= vgp.aim_stick.radius
end

-- Check if coordinates are in button
function touch.isInButton(x, y, button, vgp)
    local dx = x - button.x
    local dy = y - button.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local radius = button.radius or (vgp.button_size / 2)
    return dist <= radius
end

-- Update D-pad based on touch position
function touch.updateDPad(x, y, vgp)
    local dx = x - vgp.dpad.x
    local dy = y - vgp.dpad.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Normalize to stick values
    if dist > vgp.dpad.center_radius then
        vgp.stick_x = dx / vgp.dpad.radius
        vgp.stick_y = dy / vgp.dpad.radius

        -- Clamp to unit circle
        local length = math.sqrt(vgp.stick_x * vgp.stick_x + vgp.stick_y * vgp.stick_y)
        if length > 1 then
            vgp.stick_x = vgp.stick_x / length
            vgp.stick_y = vgp.stick_y / length
        end

        -- Update directional buttons
        vgp.dpad_direction.right = vgp.stick_x > 0.3
        vgp.dpad_direction.left = vgp.stick_x < -0.3
        vgp.dpad_direction.down = vgp.stick_y > 0.3
        vgp.dpad_direction.up = vgp.stick_y < -0.3
    else
        touch.resetDPad(vgp)
    end
end

-- Update aim stick based on touch position
function touch.updateAimStick(x, y, vgp)
    local dx = x - vgp.aim_stick.x
    local dy = y - vgp.aim_stick.y
    local distance = math.sqrt(dx * dx + dy * dy)

    -- Clamp to stick radius (leave some margin)
    local max_distance = vgp.aim_stick.radius - 20
    if distance > max_distance then
        local ratio = max_distance / distance
        dx = dx * ratio
        dy = dy * ratio
        distance = max_distance
    end

    vgp.aim_stick.offset_x = dx
    vgp.aim_stick.offset_y = dy
    vgp.aim_stick.magnitude = distance / max_distance
    vgp.aim_stick.angle = math.atan2(dy, dx)
end

-- Reset D-pad to neutral
function touch.resetDPad(vgp)
    vgp.stick_x = 0
    vgp.stick_y = 0
    vgp.dpad_direction.up = false
    vgp.dpad_direction.down = false
    vgp.dpad_direction.left = false
    vgp.dpad_direction.right = false
end

-- Reset aim stick to center
function touch.resetAimStick(vgp)
    vgp.aim_stick.active = false
    vgp.aim_stick.touch_id = nil
    vgp.aim_stick.offset_x = 0
    vgp.aim_stick.offset_y = 0
    vgp.aim_stick.angle = 0
    vgp.aim_stick.magnitude = 0
end

-- Trigger button press event
function touch.triggerButtonPress(button_name, vgp)
    local button = vgp.buttons[button_name]
    if not button then return end

    local scene_control = require "engine.core.scene_control"
    if not scene_control.current or not scene_control.current.gamepadpressed then
        return
    end

    -- Map virtual button to gamepad button action
    -- New layout: A=attack/interact, B=jump, X=parry, Y=reserved
    --             L1=use_item, L2=next_item, R1=dodge, R2=inventory
    local action = button.action

    if action == "attack_or_interact" then
        -- A button: context-based (handled in play scene)
        scene_control.current:gamepadpressed(nil, "a")
    elseif action == "jump" then
        -- B button: jump
        scene_control.current:gamepadpressed(nil, "b")
    elseif action == "parry" then
        -- X button: parry
        scene_control.current:gamepadpressed(nil, "x")
    elseif action == "reserved" then
        -- Y button: reserved for future use
        scene_control.current:gamepadpressed(nil, "y")
    elseif action == "use_item" then
        -- L1 button: use item
        scene_control.current:gamepadpressed(nil, "leftshoulder")
    elseif action == "next_item" then
        -- L2 button: next item
        scene_control.current:gamepadpressed(nil, "lefttrigger")
    elseif action == "dodge" then
        -- R1 button: dodge
        scene_control.current:gamepadpressed(nil, "rightshoulder")
    elseif action == "open_inventory" then
        -- R2 button: open inventory
        scene_control.current:gamepadpressed(nil, "righttrigger")
    end
end

-- Trigger button release event
function touch.triggerButtonRelease(button_name, vgp)
    local button = vgp.buttons[button_name]
    if not button then return end

    -- Simulate gamepad button release
    local scene_control = require "engine.core.scene_control"
    if not scene_control.current or not scene_control.current.gamepadreleased then
        return
    end

    -- Map virtual buttons to gamepad buttons
    local button_map = {
        a = "a",
        b = "b",
        x = "x",
        y = "y",
        l1 = "leftshoulder",
        l2 = "lefttrigger",
        r1 = "rightshoulder",
        r2 = "righttrigger"
    }

    local gamepad_button = button_map[button_name]
    if gamepad_button then
        scene_control.current:gamepadreleased(nil, gamepad_button)
    end
end

-- Trigger menu button press
function touch.triggerMenuPress(vgp)
    -- Trigger pause menu
    local scene_control = require "engine.core.scene_control"
    if scene_control.current and scene_control.current.gamepadpressed then
        scene_control.current:gamepadpressed(nil, "start")
    end
end

return touch

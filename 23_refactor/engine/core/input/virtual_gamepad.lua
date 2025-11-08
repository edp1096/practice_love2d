-- engine/core/input/virtual_gamepad.lua
-- Android virtual gamepad for touch controls with D-pad, aim stick, and buttons

local coords = require "engine.core.coords"
local text_ui = require "engine.utils.text"

local virtual_gamepad = {}

-- Configuration
virtual_gamepad.enabled = false
virtual_gamepad.visible = false  -- Controls whether gamepad is shown
virtual_gamepad.debug_override = false  -- If true, visible is controlled by debug mode, not scenes
virtual_gamepad.alpha = 0.5
virtual_gamepad.size = 160
virtual_gamepad.button_size = 80

-- Touch state tracking
virtual_gamepad.touches = {}
virtual_gamepad.active_buttons = {}

-- Aim stick (smaller size for space)
virtual_gamepad.aim_stick = {
    x = 0,
    y = 0,
    radius = 60,        -- Smaller than D-pad
    center_radius = 25, -- Proportionally smaller
    active = false,
    touch_id = nil,
    offset_x = 0,
    offset_y = 0,
    angle = 0,
    magnitude = 0,
    deadzone = 0.15 -- Ignore small movements
}

-- Button positions (set in init based on screen size)
virtual_gamepad.dpad = {
    x = 0,
    y = 0,
    radius = 80,
    center_radius = 30
}

virtual_gamepad.buttons = {
    -- Face buttons (diamond layout)
    a = { x = 0, y = 0, pressed = false, label = "A", action = "attack_or_interact" },  -- Attack / Interact (context)
    b = { x = 0, y = 0, pressed = false, label = "B", action = "jump" },                -- Jump (platformer only)
    x = { x = 0, y = 0, pressed = false, label = "X", action = "parry" },               -- Parry
    y = { x = 0, y = 0, pressed = false, label = "Y", action = "reserved" },            -- Reserved for future use

    -- Shoulder/Trigger buttons
    l1 = { x = 0, y = 0, pressed = false, label = "L1", action = "use_item" },          -- Use item
    l2 = { x = 0, y = 0, pressed = false, label = "L2", action = "next_item" },         -- Next item
    r1 = { x = 0, y = 0, pressed = false, label = "R1", action = "dodge" },             -- Dodge
    r2 = { x = 0, y = 0, pressed = false, label = "R2", action = "open_inventory" },    -- Open inventory
}

virtual_gamepad.menu_button = {
    x = 0,
    y = 0,
    pressed = false,
    label = "☰",
    radius = 45
}

-- D-pad direction state
virtual_gamepad.dpad_direction = {
    up = false,
    down = false,
    left = false,
    right = false
}

-- Analog stick value
virtual_gamepad.stick_x = 0
virtual_gamepad.stick_y = 0

-- Mouse aim block cooldown (prevents aim jumping to touch release position)
virtual_gamepad.mouse_aim_block_time = 0
virtual_gamepad.MOUSE_AIM_BLOCK_DURATION = 0.35

function virtual_gamepad:init()
    local os = love.system.getOS()

    -- Enable on mobile platforms
    self.enabled = (os == "Android" or os == "iOS")

    -- Get screen module for coordinate conversion (always set, even if disabled)
    self.display = require "engine.core.display"

    if not self.enabled then
        return
    end

    self:calculatePositions()
end

function virtual_gamepad:calculatePositions()
    -- Use VIRTUAL resolution (960x540) for consistent sizing across devices
    local vw, vh = self.display:GetVirtualDimensions()

    -- Move controls up to avoid covering dodge bar and to keep A button visible
    local bottom_y = vh - 100  -- Increased from 80 to 100 (moved up 20 pixels)

    -- D-pad on bottom left (moved up more)
    self.dpad.x = 100
    self.dpad.y = bottom_y - 50  -- Moved up 50 pixels more (was 30)

    -- Aim stick in center-right (between D-pad and buttons) - moved left
    self.aim_stick.x = vw * 0.65 -- 65% from left (was 70%)
    self.aim_stick.y = bottom_y

    -- Face buttons on bottom right (diamond pattern) - moved left
    local button_base_x = vw - 130  -- Moved left (was 100)
    local button_base_y = bottom_y - 20  -- Moved up 20 pixels to keep A button visible
    local button_spacing = 70

    -- Diamond layout: A (bottom), B (right), X (left), Y (top)
    self.buttons.a.x = button_base_x
    self.buttons.a.y = button_base_y + button_spacing  -- Bottom

    self.buttons.b.x = button_base_x + button_spacing
    self.buttons.b.y = button_base_y                   -- Right

    self.buttons.x.x = button_base_x - button_spacing
    self.buttons.x.y = button_base_y                   -- Left

    self.buttons.y.x = button_base_x
    self.buttons.y.y = button_base_y - button_spacing  -- Top

    -- Shoulder buttons (L1/L2 on left, R1/R2 on right)
    -- Changed to horizontal layout to reduce overlap
    -- Positioned above D-pad (left) and Y button (right) with increased gap
    local shoulder_spacing = 90  -- Increased from 75 to 90 for more spacing between L1/L2 and R1/R2
    local gap_from_controls = 30  -- Increased from 20 to 30 for better spacing

    -- Left shoulder buttons (horizontal) - above D-pad (keep original position)
    local left_shoulder_y = self.dpad.y - self.dpad.radius - gap_from_controls - (self.button_size / 2)
    self.buttons.l1.x = 60
    self.buttons.l1.y = left_shoulder_y

    self.buttons.l2.x = 60 + shoulder_spacing
    self.buttons.l2.y = left_shoulder_y

    -- Right shoulder buttons (horizontal) - above Y button (moved down more)
    local right_shoulder_y = self.buttons.y.y - button_spacing - gap_from_controls - (self.button_size / 2) + 30  -- Moved down 30 pixels (was 20)
    self.buttons.r2.x = vw - 60 - 30  -- Moved left 30 pixels to match button movement
    self.buttons.r2.y = right_shoulder_y

    self.buttons.r1.x = vw - 60 - shoulder_spacing - 30  -- Moved left 30 pixels to match button movement
    self.buttons.r1.y = right_shoulder_y

    -- Menu button on top left (left of minimap) - moved down and left
    -- Minimap is at top-right with padding of 10, size ~180
    -- Place menu button on left side with some margin
    self.menu_button.x = vw - 280  -- Moved more left (was 250)
    self.menu_button.y = 55  -- Moved down (was 40)
end

function virtual_gamepad:resize(w, h)
    if not self.enabled then return end
    self:calculatePositions()
end

function virtual_gamepad:update(dt)
    if not self.enabled then return end

    -- Decrease mouse aim block cooldown
    if self.mouse_aim_block_time > 0 then
        self.mouse_aim_block_time = math.max(0, self.mouse_aim_block_time - dt)
    end
end

function virtual_gamepad:touchpressed(id, x, y)
    if not self.enabled then return false end
    if not self.visible then return false end

    -- Convert physical touch coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    self.touches[id] = { x = vx, y = vy, start_x = vx, start_y = vy }

    -- Check D-pad (movement)
    if self:isInDPad(vx, vy) then
        self.touches[id].type = "dpad"
        self:updateDPad(vx, vy)
        -- Deactivate aim when touching D-pad
        self:resetAimStick()
        return true
    end

    -- Check action buttons
    for name, button in pairs(self.buttons) do
        if self:isInButton(vx, vy, button) then
            button.pressed = true
            self.touches[id].type = "button"
            self.touches[id].button = name
            self:triggerButtonPress(name)
            -- Deactivate aim when pressing buttons
            self:resetAimStick()
            return true
        end
    end

    -- Check menu button
    if self:isInButton(vx, vy, self.menu_button) then
        self.menu_button.pressed = true
        self.touches[id].type = "menu"
        self:triggerMenuPress()
        -- Deactivate aim when pressing menu
        self:resetAimStick()
        return true
    end

    -- Check aim stick
    if self:isInAimStick(vx, vy) then
        self.touches[id].type = "aim_stick"
        self.aim_stick.active = true
        self.aim_stick.touch_id = id
        self:updateAimStick(vx, vy)
        return true
    end

    -- No control was touched
    return false
end

function virtual_gamepad:touchreleased(id, x, y)
    if not self.enabled then return false end
    if not self.visible then return false end

    local touch = self.touches[id]
    if not touch then return false end

    if touch.type == "dpad" then
        self:resetDPad()
        self.touches[id] = nil
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch.type == "button" then
        local button = self.buttons[touch.button]
        if button then
            button.pressed = false
            self:triggerButtonRelease(touch.button)
        end
        self.touches[id] = nil
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch.type == "menu" then
        self.menu_button.pressed = false
        self.touches[id] = nil
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch.type == "aim_stick" then
        if self.aim_stick.touch_id == id then
            self:resetAimStick()
        end
        self.touches[id] = nil
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    end

    self.touches[id] = nil
    return false
end

function virtual_gamepad:touchmoved(id, x, y)
    if not self.enabled then return false end
    if not self.visible then return false end

    local touch = self.touches[id]
    if not touch then return false end

    -- Convert physical touch coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    touch.x = vx
    touch.y = vy

    if touch.type == "dpad" then
        self:updateDPad(vx, vy)
        return true
    elseif touch.type == "aim_stick" then
        self:updateAimStick(vx, vy)
        return true
    end

    return false
end

function virtual_gamepad:isInDPad(x, y)
    local dx = x - self.dpad.x
    local dy = y - self.dpad.y
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist <= self.dpad.radius
end

-- Check if touch is in aim stick area
function virtual_gamepad:isInAimStick(x, y)
    local dx = x - self.aim_stick.x
    local dy = y - self.aim_stick.y
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist <= self.aim_stick.radius
end

function virtual_gamepad:isInButton(x, y, button)
    local dx = x - button.x
    local dy = y - button.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local radius = button.radius or (self.button_size / 2)
    return dist <= radius
end

function virtual_gamepad:updateDPad(x, y)
    local dx = x - self.dpad.x
    local dy = y - self.dpad.y
    local dist = math.sqrt(dx * dx + dy * dy)

    -- Normalize to stick values
    if dist > self.dpad.center_radius then
        self.stick_x = dx / self.dpad.radius
        self.stick_y = dy / self.dpad.radius

        -- Clamp to unit circle
        local length = math.sqrt(self.stick_x * self.stick_x + self.stick_y * self.stick_y)
        if length > 1 then
            self.stick_x = self.stick_x / length
            self.stick_y = self.stick_y / length
        end

        -- Update directional buttons
        self.dpad_direction.right = self.stick_x > 0.3
        self.dpad_direction.left = self.stick_x < -0.3
        self.dpad_direction.down = self.stick_y > 0.3
        self.dpad_direction.up = self.stick_y < -0.3
    else
        self:resetDPad()
    end
end

-- Update aim stick based on touch position
function virtual_gamepad:updateAimStick(x, y)
    local dx = x - self.aim_stick.x
    local dy = y - self.aim_stick.y
    local distance = math.sqrt(dx * dx + dy * dy)

    -- Clamp to stick radius (leave some margin)
    local max_distance = self.aim_stick.radius - 20
    if distance > max_distance then
        local ratio = max_distance / distance
        dx = dx * ratio
        dy = dy * ratio
        distance = max_distance
    end

    self.aim_stick.offset_x = dx
    self.aim_stick.offset_y = dy
    self.aim_stick.magnitude = distance / max_distance
    self.aim_stick.angle = math.atan2(dy, dx)
end

function virtual_gamepad:resetDPad()
    self.stick_x = 0
    self.stick_y = 0
    self.dpad_direction.up = false
    self.dpad_direction.down = false
    self.dpad_direction.left = false
    self.dpad_direction.right = false
end

-- Reset aim stick to center
function virtual_gamepad:resetAimStick()
    self.aim_stick.active = false
    self.aim_stick.touch_id = nil
    self.aim_stick.offset_x = 0
    self.aim_stick.offset_y = 0
    self.aim_stick.angle = 0
    self.aim_stick.magnitude = 0
end


function virtual_gamepad:triggerButtonPress(button_name)
    local button = self.buttons[button_name]
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

function virtual_gamepad:triggerButtonRelease(button_name)
    local button = self.buttons[button_name]
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

function virtual_gamepad:triggerMenuPress()
    -- Trigger pause menu
    local scene_control = require "engine.core.scene_control"
    if scene_control.current and scene_control.current.gamepadpressed then
        scene_control.current:gamepadpressed(nil, "start")
    end
end

-- Get analog stick values (for movement)
function virtual_gamepad:getStickAxis()
    if not self.enabled then
        return 0, 0
    end
    return self.stick_x, self.stick_y
end

-- Get aim direction from aim stick
function virtual_gamepad:getAimDirection(player_x, player_y, cam)
    if not self.enabled then
        return nil, false
    end

    -- Use aim stick if active and moved beyond deadzone
    if self.aim_stick.active and self.aim_stick.magnitude > self.aim_stick.deadzone then
        return self.aim_stick.angle, true
    end

    return nil, false
end

-- Check if direction is pressed
function virtual_gamepad:isDirectionPressed(direction)
    if not self.enabled then
        return false
    end
    return self.dpad_direction[direction] or false
end

-- Helper function to convert virtual to physical coordinates
function virtual_gamepad:toPhysical(vx, vy)
    return coords:virtualToPhysical(vx, vy, self.display)
end

-- Draw virtual gamepad overlay
function virtual_gamepad:draw()
    if not self.enabled or not self.visible then return end

    -- Cache scale for drawing
    self.draw_scale = self.display:GetScale()

    -- No push/pop/origin needed - we draw in physical space after display:Detach()
    -- Draw D-pad
    self:drawDPad()

    -- Draw aim stick
    self:drawAimStick()

    -- Draw action buttons
    self:drawActionButtons()

    -- Draw menu button
    self:drawMenuButton()
end

function virtual_gamepad:drawDPad()
    -- Convert virtual coordinates to physical coordinates
    local px, py = self:toPhysical(self.dpad.x, self.dpad.y)
    local scale = self.draw_scale or 1
    local r = self.dpad.radius * scale

    -- Outer circle
    love.graphics.setColor(0.2, 0.2, 0.2, self.alpha)
    love.graphics.circle("fill", px, py, r)
    love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.5)
    love.graphics.setLineWidth(3 * scale)
    love.graphics.circle("line", px, py, r)

    -- Directional indicators
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)

    -- Up arrow
    if self.dpad_direction.up then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        px, py - r + 20 * scale,
        px - 18 * scale, py - r + 45 * scale,
        px + 18 * scale, py - r + 45 * scale
    )

    -- Down arrow
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)
    if self.dpad_direction.down then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        px, py + r - 20 * scale,
        px - 18 * scale, py + r - 45 * scale,
        px + 18 * scale, py + r - 45 * scale
    )

    -- Left arrow
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)
    if self.dpad_direction.left then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        px - r + 20 * scale, py,
        px - r + 45 * scale, py - 18 * scale,
        px - r + 45 * scale, py + 18 * scale
    )

    -- Right arrow
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)
    if self.dpad_direction.right then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        px + r - 20 * scale, py,
        px + r - 45 * scale, py - 18 * scale,
        px + r - 45 * scale, py + 18 * scale
    )

    -- Center knob
    local knob_x = px + (self.stick_x * (r - 30 * scale))
    local knob_y = py + (self.stick_y * (r - 30 * scale))

    love.graphics.setColor(0.3, 0.3, 0.3, self.alpha * 1.2)
    love.graphics.circle("fill", knob_x, knob_y, self.dpad.center_radius * scale)
    love.graphics.setColor(0.6, 0.6, 0.6, self.alpha * 1.5)
    love.graphics.setLineWidth(2 * scale)
    love.graphics.circle("line", knob_x, knob_y, self.dpad.center_radius * scale)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw aim stick
function virtual_gamepad:drawAimStick()
    local stick = self.aim_stick
    local px, py = self:toPhysical(stick.x, stick.y)
    local scale = self.draw_scale or 1
    local r = stick.radius * scale

    -- Outer circle (base)
    love.graphics.setColor(0.2, 0.2, 0.2, self.alpha * 0.7)
    love.graphics.circle("fill", px, py, r)
    love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.2)
    love.graphics.setLineWidth(3 * scale)
    love.graphics.circle("line", px, py, r)

    -- Center crosshair indicator
    love.graphics.setColor(0.6, 0.6, 0.6, self.alpha * 0.8)
    love.graphics.setLineWidth(2 * scale)
    local cross_size = 12 * scale
    love.graphics.line(px - cross_size, py, px + cross_size, py)
    love.graphics.line(px, py - cross_size, px, py + cross_size)

    -- Inner stick position
    local stick_px = px + stick.offset_x * scale
    local stick_py = py + stick.offset_y * scale

    -- Direction line (if active)
    if stick.active and stick.magnitude > stick.deadzone then
        love.graphics.setColor(1, 1, 0, self.alpha * 1.2)
        love.graphics.setLineWidth(3 * scale)
        love.graphics.line(px, py, stick_px, stick_py)
    end

    -- Stick knob
    if stick.active then
        -- Active - yellow/gold
        love.graphics.setColor(1, 0.9, 0, self.alpha * 1.5)
    else
        -- Inactive - gray
        love.graphics.setColor(0.3, 0.3, 0.3, self.alpha * 1.2)
    end
    love.graphics.circle("fill", stick_px, stick_py, stick.center_radius * scale)

    -- Stick outline
    if stick.active then
        love.graphics.setColor(1, 1, 0.5, self.alpha * 1.8)
    else
        love.graphics.setColor(0.6, 0.6, 0.6, self.alpha * 1.5)
    end
    love.graphics.setLineWidth(2 * scale)
    love.graphics.circle("line", stick_px, stick_py, stick.center_radius * scale)

    -- Label
    text_ui:draw("AIM", px - 15 * scale, py + r + 10 * scale, {1, 1, 1, self.alpha * 1.5})

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function virtual_gamepad:drawActionButtons()
    local scale = self.draw_scale or 1

    for name, button in pairs(self.buttons) do
        local px, py = self:toPhysical(button.x, button.y)
        local radius = (self.button_size / 2) * scale

        -- Button circle
        if button.pressed then
            love.graphics.setColor(0.3, 0.6, 1.0, self.alpha * 1.5)
        else
            love.graphics.setColor(0.2, 0.2, 0.2, self.alpha)
        end
        love.graphics.circle("fill", px, py, radius)

        -- Button outline
        if button.pressed then
            love.graphics.setColor(0.5, 0.8, 1.0, self.alpha * 2)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.5)
        end
        love.graphics.setLineWidth(3 * scale)
        love.graphics.circle("line", px, py, radius)

        -- Button label
        local font = love.graphics.getFont()
        local text_w = font:getWidth(button.label)
        local text_h = font:getHeight()
        text_ui:draw(button.label, px - text_w / 2, py - text_h / 2, {1, 1, 1, self.alpha * 2})
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function virtual_gamepad:drawMenuButton()
    local button = self.menu_button
    local px, py = self:toPhysical(button.x, button.y)
    local scale = self.draw_scale or 1
    local radius = button.radius * scale

    -- Button circle
    if button.pressed then
        love.graphics.setColor(0.3, 0.6, 1.0, self.alpha * 1.5)
    else
        love.graphics.setColor(0.2, 0.2, 0.2, self.alpha)
    end
    love.graphics.circle("fill", px, py, radius)

    -- Button outline
    if button.pressed then
        love.graphics.setColor(0.5, 0.8, 1.0, self.alpha * 2)
    else
        love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.5)
    end
    love.graphics.setLineWidth(3 * scale)
    love.graphics.circle("line", px, py, radius)

    -- Button label
    local font = love.graphics.getFont()
    local text_w = font:getWidth(button.label)
    local text_h = font:getHeight()
    text_ui:draw(button.label, px - text_w / 2, py - text_h / 2, {1, 1, 1, self.alpha * 2})

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end


-- Toggle visibility
function virtual_gamepad:toggle()
    if not self.enabled then return end
    self.alpha = (self.alpha > 0) and 0 or 0.5
end

function virtual_gamepad:setAlpha(alpha)
    self.alpha = math.max(0, math.min(1, alpha))
end

-- Check if coordinates are in any virtual gamepad control area
-- NOTE: x, y are physical coordinates from touch input
function virtual_gamepad:isInVirtualPadArea(x, y)
    if not self.enabled then return false end

    -- Convert physical coordinates to virtual coordinates using coords module
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    -- Check D-pad
    if self:isInDPad(vx, vy) then
        return true
    end

    -- Check aim stick
    if self:isInAimStick(vx, vy) then
        return true
    end

    -- Check action buttons
    for _, button in pairs(self.buttons) do
        if self:isInButton(vx, vy, button) then
            return true
        end
    end

    -- Check menu button
    if self:isInButton(vx, vy, self.menu_button) then
        return true
    end

    return false
end

-- Check if virtual gamepad is currently handling any touches
function virtual_gamepad:hasActiveTouches()
    if not self.enabled then return false end

    -- Check if mouse aim is blocked
    if self.mouse_aim_block_time > 0 then
        return true
    end

    -- Check if any touch is being tracked
    for id, touch in pairs(self.touches) do
        if touch.type == "dpad" or
            touch.type == "button" or
            touch.type == "menu" or
            touch.type == "aim_stick" then
            return true
        end
    end

    return false
end

-- Show virtual gamepad (for gameplay scenes)
function virtual_gamepad:show()
    if not self.enabled then return end
    if self.debug_override then return end  -- Don't change visibility in debug mode
    self.visible = true
end

-- Hide virtual gamepad (for menu scenes)
function virtual_gamepad:hide()
    if not self.enabled then return end
    if self.debug_override then return end  -- Don't change visibility in debug mode
    self.visible = false
    -- Reset all touch states when hiding
    self:resetDPad()
    self:resetAimStick()
    self.touches = {}
    for _, button in pairs(self.buttons) do
        button.pressed = false
    end
    self.menu_button.pressed = false
end

return virtual_gamepad

-- systems/input/virtual_gamepad.lua
-- Android virtual gamepad for touch controls with D-pad, aim stick, and buttons
-- MODIFIED: Added aim stick for better aiming control

local virtual_gamepad = {}

-- Configuration
virtual_gamepad.enabled = false
virtual_gamepad.visible = false  -- Controls whether gamepad is shown
virtual_gamepad.alpha = 0.5
virtual_gamepad.size = 160
virtual_gamepad.button_size = 80

-- Touch state tracking
virtual_gamepad.touches = {}
virtual_gamepad.active_buttons = {}

-- OLD: Direct aim touch state (kept as fallback)
virtual_gamepad.aim_touch = {
    active = false,
    id = nil,
    x = 0,
    y = 0,
    angle = 0
}

-- NEW: Aim stick (smaller size for space)
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
    local debug = require "systems.debug"

    -- Enable on mobile OR when debug mode is active on PC
    self.enabled = (os == "Android" or os == "iOS") or debug.debug_mode

    if not self.enabled then
        return
    end

    self:calculatePositions()
    if debug.debug_mode then
        print("Virtual gamepad initialized (DEBUG MODE)")
    else
        print("Virtual gamepad initialized for " .. os)
    end
end

function virtual_gamepad:calculatePositions()
    local w, h = love.graphics.getDimensions()

    -- All controls at same bottom level
    local bottom_y = h - 120

    -- D-pad on bottom left
    self.dpad.x = 120
    self.dpad.y = bottom_y

    -- Aim stick in center-right (between D-pad and buttons)
    self.aim_stick.x = w * 0.70 -- 70% from left (center-right)
    self.aim_stick.y = bottom_y -- Same level as D-pad

    -- Face buttons on bottom right (diamond pattern)
    local button_base_x = w - 120
    local button_base_y = bottom_y
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
    local shoulder_y_top = 80
    local shoulder_y_bottom = 140

    -- Left shoulder buttons
    self.buttons.l1.x = 100
    self.buttons.l1.y = shoulder_y_top

    self.buttons.l2.x = 100
    self.buttons.l2.y = shoulder_y_bottom

    -- Right shoulder buttons
    self.buttons.r1.x = w - 100
    self.buttons.r1.y = shoulder_y_top

    self.buttons.r2.x = w - 100
    self.buttons.r2.y = shoulder_y_bottom

    -- Menu button on top center
    self.menu_button.x = w / 2
    self.menu_button.y = 60
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

    self.touches[id] = { x = x, y = y, start_x = x, start_y = y }

    -- Check D-pad (movement)
    if self:isInDPad(x, y) then
        self.touches[id].type = "dpad"
        self:updateDPad(x, y)
        -- Deactivate aim when touching D-pad
        if self.aim_touch.active then
            self.aim_touch.active = false
            self.aim_touch.id = nil
        end
        if self.aim_stick.active then
            self:resetAimStick()
        end
        return true
    end

    -- Check action buttons
    for name, button in pairs(self.buttons) do
        if self:isInButton(x, y, button) then
            button.pressed = true
            self.touches[id].type = "button"
            self.touches[id].button = name
            self:triggerButtonPress(name)
            -- Deactivate aim when pressing buttons
            if self.aim_touch.active then
                self.aim_touch.active = false
                self.aim_touch.id = nil
            end
            if self.aim_stick.active then
                self:resetAimStick()
            end
            return true
        end
    end

    -- Check menu button
    if self:isInButton(x, y, self.menu_button) then
        self.menu_button.pressed = true
        self.touches[id].type = "menu"
        self:triggerMenuPress()
        -- Deactivate aim when pressing menu
        if self.aim_touch.active then
            self.aim_touch.active = false
            self.aim_touch.id = nil
        end
        if self.aim_stick.active then
            self:resetAimStick()
        end
        return true
    end

    -- NEW: Check aim stick
    if self:isInAimStick(x, y) then
        self.touches[id].type = "aim_stick"
        self.aim_stick.active = true
        self.aim_stick.touch_id = id
        self:updateAimStick(x, y)
        -- Deactivate direct aim
        if self.aim_touch.active then
            self.aim_touch.active = false
            self.aim_touch.id = nil
        end
        return true
    end

    -- Fallback: Direct aim touch (legacy support)
    self.touches[id].type = "aim"
    self.aim_touch.active = true
    self.aim_touch.id = id
    self.aim_touch.x = x
    self.aim_touch.y = y
    return true
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
        -- NEW: Release aim stick
        if self.aim_stick.touch_id == id then
            self:resetAimStick()
        end
        self.touches[id] = nil
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch.type == "aim" then
        -- Release direct aim touch
        if self.aim_touch.id == id then
            self.aim_touch.active = false
            self.aim_touch.id = nil
        end
        self.touches[id] = nil
        return false
    end

    self.touches[id] = nil
    return false
end

function virtual_gamepad:touchmoved(id, x, y)
    if not self.enabled then return false end
    if not self.visible then return false end

    local touch = self.touches[id]
    if not touch then return false end

    touch.x = x
    touch.y = y

    if touch.type == "dpad" then
        self:updateDPad(x, y)
        return true
    elseif touch.type == "aim_stick" then
        -- NEW: Update aim stick
        self:updateAimStick(x, y)
        return true
    elseif touch.type == "aim" then
        -- Update direct aim position
        self.aim_touch.x = x
        self.aim_touch.y = y
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

-- NEW: Check if touch is in aim stick area
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

-- NEW: Update aim stick based on touch position
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

-- NEW: Reset aim stick to center
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

    local scene_control = require "systems.scene_control"
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
    local scene_control = require "systems.scene_control"
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
    local scene_control = require "systems.scene_control"
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

-- MODIFIED: Get aim direction (prioritizes aim stick over direct aim)
function virtual_gamepad:getAimDirection(player_x, player_y, cam)
    if not self.enabled then
        return nil, false
    end

    -- NEW: Use aim stick if active
    if self.aim_stick.active and self.aim_stick.magnitude > self.aim_stick.deadzone then
        return self.aim_stick.angle, true
    end

    -- Fallback to direct aim touch (legacy support)
    if not self.aim_touch.active then
        return nil, false
    end

    -- Touch position is already in screen coordinates
    local screen_touch_x = self.aim_touch.x
    local screen_touch_y = self.aim_touch.y

    -- Convert player world position to screen coordinates
    local screen_player_x, screen_player_y
    if cam then
        screen_player_x, screen_player_y = cam:cameraCoords(player_x, player_y)
    else
        screen_player_x, screen_player_y = player_x, player_y
    end

    -- Calculate square aim area using actual screen height
    local screen = require "lib.screen"
    local aim_area_size = screen.screen_wh.h
    local half_area = aim_area_size / 2

    -- Check distance in screen coordinates
    local dx = screen_touch_x - screen_player_x
    local dy = screen_touch_y - screen_player_y

    -- If outside aim area, deactivate and return
    if math.abs(dx) > half_area or math.abs(dy) > half_area then
        self.aim_touch.active = false
        self.aim_touch.id = nil
        return nil, false
    end

    -- Calculate angle in world coordinates
    local world_touch_x, world_touch_y
    if cam then
        world_touch_x, world_touch_y = cam:worldCoords(screen_touch_x, screen_touch_y)
    else
        world_touch_x, world_touch_y = screen_touch_x, screen_touch_y
    end

    local angle = math.atan2(world_touch_y - player_y, world_touch_x - player_x)

    return angle, true
end

-- Check if direction is pressed
function virtual_gamepad:isDirectionPressed(direction)
    if not self.enabled then
        return false
    end
    return self.dpad_direction[direction] or false
end

-- Draw virtual gamepad overlay
function virtual_gamepad:draw()
    if not self.enabled or not self.visible then return end

    -- Draw D-pad
    self:drawDPad()

    -- NEW: Draw aim stick
    self:drawAimStick()

    -- Draw action buttons
    self:drawActionButtons()

    -- Draw menu button
    self:drawMenuButton()

    -- Draw direct aim indicator (only if not using aim stick)
    if not self.aim_stick.active then
        self:drawAimIndicator()
    end
end

function virtual_gamepad:drawDPad()
    local x = self.dpad.x
    local y = self.dpad.y
    local r = self.dpad.radius

    -- Outer circle
    love.graphics.setColor(0.2, 0.2, 0.2, self.alpha)
    love.graphics.circle("fill", x, y, r)
    love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.5)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, r)

    -- Directional indicators
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)

    -- Up arrow
    if self.dpad_direction.up then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        x, y - r + 20,
        x - 18, y - r + 45,
        x + 18, y - r + 45
    )

    -- Down arrow
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)
    if self.dpad_direction.down then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        x, y + r - 20,
        x - 18, y + r - 45,
        x + 18, y + r - 45
    )

    -- Left arrow
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)
    if self.dpad_direction.left then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        x - r + 20, y,
        x - r + 45, y - 18,
        x - r + 45, y + 18
    )

    -- Right arrow
    love.graphics.setColor(0.4, 0.4, 0.4, self.alpha)
    if self.dpad_direction.right then
        love.graphics.setColor(0.8, 0.8, 1.0, self.alpha * 2)
    end
    love.graphics.polygon("fill",
        x + r - 20, y,
        x + r - 45, y - 18,
        x + r - 45, y + 18
    )

    -- Center knob
    local knob_x = x + (self.stick_x * (r - 30))
    local knob_y = y + (self.stick_y * (r - 30))

    love.graphics.setColor(0.3, 0.3, 0.3, self.alpha * 1.2)
    love.graphics.circle("fill", knob_x, knob_y, self.dpad.center_radius)
    love.graphics.setColor(0.6, 0.6, 0.6, self.alpha * 1.5)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", knob_x, knob_y, self.dpad.center_radius)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

-- NEW: Draw aim stick
function virtual_gamepad:drawAimStick()
    local stick = self.aim_stick
    local x = stick.x
    local y = stick.y
    local r = stick.radius

    -- Outer circle (base)
    love.graphics.setColor(0.2, 0.2, 0.2, self.alpha * 0.7)
    love.graphics.circle("fill", x, y, r)
    love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.2)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", x, y, r)

    -- Center crosshair indicator
    love.graphics.setColor(0.6, 0.6, 0.6, self.alpha * 0.8)
    love.graphics.setLineWidth(2)
    local cross_size = 12
    love.graphics.line(x - cross_size, y, x + cross_size, y)
    love.graphics.line(x, y - cross_size, x, y + cross_size)

    -- Inner stick position
    local stick_x = x + stick.offset_x
    local stick_y = y + stick.offset_y

    -- Direction line (if active)
    if stick.active and stick.magnitude > stick.deadzone then
        love.graphics.setColor(1, 1, 0, self.alpha * 1.2)
        love.graphics.setLineWidth(3)
        love.graphics.line(x, y, stick_x, stick_y)
    end

    -- Stick knob
    if stick.active then
        -- Active - yellow/gold
        love.graphics.setColor(1, 0.9, 0, self.alpha * 1.5)
    else
        -- Inactive - gray
        love.graphics.setColor(0.3, 0.3, 0.3, self.alpha * 1.2)
    end
    love.graphics.circle("fill", stick_x, stick_y, stick.center_radius)

    -- Stick outline
    if stick.active then
        love.graphics.setColor(1, 1, 0.5, self.alpha * 1.8)
    else
        love.graphics.setColor(0.6, 0.6, 0.6, self.alpha * 1.5)
    end
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", stick_x, stick_y, stick.center_radius)

    -- Label
    love.graphics.setColor(1, 1, 1, self.alpha * 1.5)
    love.graphics.print("AIM", x - 15, y + r + 10)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function virtual_gamepad:drawActionButtons()
    for name, button in pairs(self.buttons) do
        local radius = self.button_size / 2

        -- Button circle
        if button.pressed then
            love.graphics.setColor(0.3, 0.6, 1.0, self.alpha * 1.5)
        else
            love.graphics.setColor(0.2, 0.2, 0.2, self.alpha)
        end
        love.graphics.circle("fill", button.x, button.y, radius)

        -- Button outline
        if button.pressed then
            love.graphics.setColor(0.5, 0.8, 1.0, self.alpha * 2)
        else
            love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.5)
        end
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", button.x, button.y, radius)

        -- Button label
        love.graphics.setColor(1, 1, 1, self.alpha * 2)
        local font = love.graphics.getFont()
        local text_w = font:getWidth(button.label)
        local text_h = font:getHeight()
        love.graphics.print(button.label, button.x - text_w / 2, button.y - text_h / 2)
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function virtual_gamepad:drawMenuButton()
    local button = self.menu_button
    local radius = button.radius

    -- Button circle
    if button.pressed then
        love.graphics.setColor(0.3, 0.6, 1.0, self.alpha * 1.5)
    else
        love.graphics.setColor(0.2, 0.2, 0.2, self.alpha)
    end
    love.graphics.circle("fill", button.x, button.y, radius)

    -- Button outline
    if button.pressed then
        love.graphics.setColor(0.5, 0.8, 1.0, self.alpha * 2)
    else
        love.graphics.setColor(0.5, 0.5, 0.5, self.alpha * 1.5)
    end
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", button.x, button.y, radius)

    -- Button label
    love.graphics.setColor(1, 1, 1, self.alpha * 2)
    local font = love.graphics.getFont()
    local text_w = font:getWidth(button.label)
    local text_h = font:getHeight()
    love.graphics.print(button.label, button.x - text_w / 2, button.y - text_h / 2)

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function virtual_gamepad:drawAimIndicator()
    if not self.aim_touch.active then return end

    -- Draw crosshair at touch position
    local x = self.aim_touch.x
    local y = self.aim_touch.y
    local size = 20

    love.graphics.setColor(1, 0, 0, self.alpha * 2)
    love.graphics.setLineWidth(3)

    -- Horizontal line
    love.graphics.line(x - size, y, x + size, y)
    -- Vertical line
    love.graphics.line(x, y - size, x, y + size)

    -- Outer circle
    love.graphics.circle("line", x, y, size + 5)

    -- Inner dot
    love.graphics.circle("fill", x, y, 4)

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
function virtual_gamepad:isInVirtualPadArea(x, y)
    if not self.enabled then return false end

    -- Check D-pad
    if self:isInDPad(x, y) then
        return true
    end

    -- NEW: Check aim stick
    if self:isInAimStick(x, y) then
        return true
    end

    -- Check action buttons
    for _, button in pairs(self.buttons) do
        if self:isInButton(x, y, button) then
            return true
        end
    end

    -- Check menu button
    if self:isInButton(x, y, self.menu_button) then
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
    self.visible = true
end

-- Hide virtual gamepad (for menu scenes)
function virtual_gamepad:hide()
    if not self.enabled then return end
    self.visible = false
    -- Reset all touch states when hiding
    self:resetDPad()
    self:resetAimStick()
    self.touches = {}
    for _, button in pairs(self.buttons) do
        button.pressed = false
    end
    self.menu_button.pressed = false
    if self.aim_touch.active then
        self.aim_touch.active = false
        self.aim_touch.id = nil
    end
end

return virtual_gamepad

-- systems/virtual_gamepad.lua
-- Android virtual gamepad for touch controls with D-pad and buttons

local virtual_gamepad = {}

-- Configuration
virtual_gamepad.enabled = false
virtual_gamepad.alpha = 0.5
virtual_gamepad.size = 160
virtual_gamepad.button_size = 100

-- Touch state tracking
virtual_gamepad.touches = {}
virtual_gamepad.active_buttons = {}

-- Aim touch state (separate from button presses)
virtual_gamepad.aim_touch = {
    active = false,
    id = nil,
    x = 0,
    y = 0,
    angle = 0
}

-- Button positions (set in init based on screen size)
virtual_gamepad.dpad = {
    x = 0,
    y = 0,
    radius = 80,
    center_radius = 30
}

virtual_gamepad.buttons = {
    a = { x = 0, y = 0, pressed = false, label = "A", action = "attack" },
    b = { x = 0, y = 0, pressed = false, label = "B", action = "dodge" },
    x = { x = 0, y = 0, pressed = false, label = "X", action = "parry" },
    y = { x = 0, y = 0, pressed = false, label = "Y", action = "interact" },
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
    -- Detect if we're on Android
    local os = love.system.getOS()
    self.enabled = (os == "Android" or os == "iOS")

    if not self.enabled then
        return
    end

    self:calculatePositions()
    print("Virtual gamepad initialized for " .. os)
end

function virtual_gamepad:calculatePositions()
    local w, h = love.graphics.getDimensions()

    -- D-pad on bottom left (adjusted for larger size)
    self.dpad.x = 120
    self.dpad.y = h - 140

    -- Action buttons on bottom right (adjusted for larger size)
    local button_base_x = w - 120
    local button_base_y = h - 140

    -- Button layout (diamond pattern with larger spacing)
    self.buttons.a.x = button_base_x
    self.buttons.a.y = button_base_y + 70

    self.buttons.b.x = button_base_x + 70
    self.buttons.b.y = button_base_y

    self.buttons.x.x = button_base_x - 70
    self.buttons.x.y = button_base_y

    self.buttons.y.x = button_base_x
    self.buttons.y.y = button_base_y - 70

    -- Menu button on top right (slightly larger)
    self.menu_button.x = w - 60
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
    if not self.enabled then return end

    self.touches[id] = { x = x, y = y, start_x = x, start_y = y }

    -- Check D-pad
    if self:isInDPad(x, y) then
        self.touches[id].type = "dpad"
        self:updateDPad(x, y)
        -- Deactivate aim touch when touching D-pad (prevents aim pointing left)
        if self.aim_touch.active then
            self.aim_touch.active = false
            self.aim_touch.id = nil
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
            -- Deactivate aim touch when pressing buttons
            if self.aim_touch.active then
                self.aim_touch.active = false
                self.aim_touch.id = nil
            end
            return true
        end
    end

    -- Check menu button
    if self:isInButton(x, y, self.menu_button) then
        self.menu_button.pressed = true
        self.touches[id].type = "menu"
        self:triggerMenuPress()
        -- Deactivate aim touch when pressing menu button
        if self.aim_touch.active then
            self.aim_touch.active = false
            self.aim_touch.id = nil
        end
        return true
    end

    -- If not in any virtual pad area, treat as aim touch
    self.touches[id].type = "aim"
    self.aim_touch.active = true
    self.aim_touch.id = id
    self.aim_touch.x = x
    self.aim_touch.y = y
    -- Don't trigger attack, just set aim direction
    return true
end

function virtual_gamepad:touchreleased(id, x, y)
    if not self.enabled then return false end

    local touch = self.touches[id]
    if not touch then return false end

    if touch.type == "dpad" then
        self:resetDPad()
        self.touches[id] = nil
        -- Block mouse aim briefly to prevent aim snapping to release position
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch.type == "button" then
        local button = self.buttons[touch.button]
        if button then
            button.pressed = false
            self:triggerButtonRelease(touch.button)
        end
        self.touches[id] = nil
        -- Block mouse aim briefly
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch.type == "menu" then
        self.menu_button.pressed = false
        self.touches[id] = nil
        -- Block mouse aim briefly
        self.mouse_aim_block_time = self.MOUSE_AIM_BLOCK_DURATION
        return true
    elseif touch.type == "aim" then
        -- Release aim touch
        if self.aim_touch.id == id then
            self.aim_touch.active = false
            self.aim_touch.id = nil
        end
        self.touches[id] = nil
        -- Return false so scene can handle it (allows menu touches to work)
        return false
    end

    self.touches[id] = nil
    return false
end

function virtual_gamepad:touchmoved(id, x, y)
    if not self.enabled then return end

    local touch = self.touches[id]
    if not touch then return false end

    touch.x = x
    touch.y = y

    if touch.type == "dpad" then
        self:updateDPad(x, y)
        return true
    elseif touch.type == "aim" then
        -- Update aim position
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

function virtual_gamepad:resetDPad()
    self.stick_x = 0
    self.stick_y = 0
    self.dpad_direction.up = false
    self.dpad_direction.down = false
    self.dpad_direction.left = false
    self.dpad_direction.right = false
end

function virtual_gamepad:triggerButtonPress(button_name)
    local input = require "systems.input"
    local button = self.buttons[button_name]

    if not button then return end

    -- Simulate gamepad button press
    if button.action == "attack" then
        -- Trigger attack via input system
        local scene_control = require "systems.scene_control"
        if scene_control.current and scene_control.current.gamepadpressed then
            scene_control.current:gamepadpressed(nil, "a")
        end
    elseif button.action == "dodge" then
        local scene_control = require "systems.scene_control"
        if scene_control.current and scene_control.current.gamepadpressed then
            scene_control.current:gamepadpressed(nil, "b")
        end
    elseif button.action == "parry" then
        local scene_control = require "systems.scene_control"
        if scene_control.current and scene_control.current.gamepadpressed then
            scene_control.current:gamepadpressed(nil, "x")
        end
    elseif button.action == "interact" then
        local scene_control = require "systems.scene_control"
        if scene_control.current and scene_control.current.gamepadpressed then
            scene_control.current:gamepadpressed(nil, "y")
        end
    end
end

function virtual_gamepad:triggerButtonRelease(button_name)
    local button = self.buttons[button_name]
    if not button then return end

    -- Simulate gamepad button release
    local scene_control = require "systems.scene_control"
    if scene_control.current and scene_control.current.gamepadreleased then
        local button_map = {
            a = "a",
            b = "b",
            x = "x",
            y = "y"
        }
        scene_control.current:gamepadreleased(nil, button_map[button_name])
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

-- Get aim direction (returns angle and whether aim touch is active)
-- Get aim direction (returns angle and whether aim touch is active)
function virtual_gamepad:getAimDirection(player_x, player_y, cam)
    if not self.enabled or not self.aim_touch.active then
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
    local aim_area_size = screen.screen_wh.h -- Actual screen pixel height
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
    if not self.enabled then return end

    -- Draw D-pad
    self:drawDPad()

    -- Draw action buttons
    self:drawActionButtons()

    -- Draw menu button
    self:drawMenuButton()

    -- Draw aim indicator
    self:drawAimIndicator()
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

    -- Directional indicators (scaled for larger D-pad)
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

    -- Center indicator (current stick position)
    if self.stick_x ~= 0 or self.stick_y ~= 0 then
        love.graphics.setColor(1.0, 1.0, 1.0, self.alpha * 2)
        local indicator_x = x + self.stick_x * (r - 20)
        local indicator_y = y + self.stick_y * (r - 20)
        love.graphics.circle("fill", indicator_x, indicator_y, 15)
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function virtual_gamepad:drawActionButtons()
    for name, button in pairs(self.buttons) do
        local alpha = button.pressed and (self.alpha * 2) or self.alpha

        -- Button background
        love.graphics.setColor(0.2, 0.2, 0.2, alpha)
        love.graphics.circle("fill", button.x, button.y, self.button_size / 2)

        -- Button border
        love.graphics.setColor(0.6, 0.6, 0.6, alpha * 1.5)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", button.x, button.y, self.button_size / 2)

        -- Button label
        love.graphics.setColor(1, 1, 1, alpha * 2)
        local font = love.graphics.newFont(28)
        love.graphics.setFont(font)
        local text_width = font:getWidth(button.label)
        local text_height = font:getHeight()
        love.graphics.print(button.label,
            button.x - text_width / 2,
            button.y - text_height / 2)
    end

    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function virtual_gamepad:drawMenuButton()
    local button = self.menu_button
    local alpha = button.pressed and (self.alpha * 2) or self.alpha
    local radius = button.radius

    -- Button background
    love.graphics.setColor(0.2, 0.2, 0.2, alpha)
    love.graphics.circle("fill", button.x, button.y, radius)

    -- Button border
    love.graphics.setColor(0.6, 0.6, 0.6, alpha * 1.5)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", button.x, button.y, radius)

    -- Menu icon (hamburger)
    love.graphics.setColor(1, 1, 1, alpha * 2)
    local font = love.graphics.newFont(32)
    love.graphics.setFont(font)
    local text_width = font:getWidth(button.label)
    local text_height = font:getHeight()
    love.graphics.print(button.label,
        button.x - text_width / 2,
        button.y - text_height / 2)

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

    -- Check if mouse aim is blocked (cooldown after releasing controls)
    if self.mouse_aim_block_time > 0 then
        return true
    end

    -- Check if any touch is being tracked
    for id, touch in pairs(self.touches) do
        if touch.type == "dpad" or touch.type == "button" or touch.type == "menu" then
            return true
        end
    end

    return false
end

return virtual_gamepad

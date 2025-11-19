-- engine/core/input/virtual_gamepad/init.lua
-- Android virtual gamepad for touch controls with D-pad, aim stick, and buttons

local coords = require "engine.core.coords"
local renderer = require "engine.core.input.virtual_gamepad.renderer"
local touch = require "engine.core.input.virtual_gamepad.touch"

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
    b = { x = 0, y = 0, pressed = false, label = "B", action = "jump" },                -- Jump (physics/visual depending on mode)
    x = { x = 0, y = 0, pressed = false, label = "X", action = "parry" },               -- Parry
    y = { x = 0, y = 0, pressed = false, label = "Y", action = "reserved" },            -- Reserved for future use

    -- Shoulder/Trigger buttons
    l1 = { x = 0, y = 0, pressed = false, label = "L1", action = "open_inventory" },        -- Open Inventory
    l2 = { x = 0, y = 0, pressed = false, label = "L2", action = "open_questlog" },         -- Open Quest Log
    r1 = { x = 0, y = 0, pressed = false, label = "R1", action = "dodge" },                 -- Dodge
    r2 = { x = 0, y = 0, pressed = false, label = "R2", action = "evade" },                 -- Evade (stationary invincibility)
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
    self.aim_stick.y = bottom_y - 45

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
    return touch.handlePress(id, x, y, self)
end

function virtual_gamepad:touchreleased(id, x, y)
    return touch.handleRelease(id, x, y, self)
end

function virtual_gamepad:touchmoved(id, x, y)
    return touch.handleMove(id, x, y, self)
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
    renderer.draw(self)
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
    if touch.isInDPad(vx, vy, self) then
        return true
    end

    -- Check aim stick
    if touch.isInAimStick(vx, vy, self) then
        return true
    end

    -- Check action buttons
    for _, button in pairs(self.buttons) do
        if touch.isInButton(vx, vy, button, self) then
            return true
        end
    end

    -- Check menu button
    if touch.isInButton(vx, vy, self.menu_button, self) then
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
    for id, touch_data in pairs(self.touches) do
        if touch_data.type == "dpad" or
            touch_data.type == "button" or
            touch_data.type == "menu" or
            touch_data.type == "aim_stick" then
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
    touch.resetDPad(self)
    touch.resetAimStick(self)
    self.touches = {}
    for _, button in pairs(self.buttons) do
        button.pressed = false
    end
    self.menu_button.pressed = false
end

return virtual_gamepad

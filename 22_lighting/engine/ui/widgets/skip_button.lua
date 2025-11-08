-- engine/ui/widgets/skip_button.lua
-- Reusable SKIP button widget for mobile UI (dialogue, cutscenes)

local coords = require "engine.coords"

local skip_button = {}

-- Create a new skip button instance
function skip_button:new(options)
    options = options or {}

    local instance = {
        -- Position (virtual coordinates, default: bottom-right)
        x = options.x or nil,  -- nil = auto-calculate
        y = options.y or nil,  -- nil = auto-calculate

        -- Size
        width = options.width or 120,
        height = options.height or 50,

        -- Padding from screen edges
        padding_x = options.padding_x or 20,
        padding_y = options.padding_y or 20,

        -- Appearance
        label = options.label or "SKIP",
        font = options.font or love.graphics.newFont(16),

        -- Colors
        bg_color = options.bg_color or {0.2, 0.2, 0.2, 0.8},
        bg_hover_color = options.bg_hover_color or {0.3, 0.3, 0.3, 0.9},
        border_color = options.border_color or {0.6, 0.6, 0.6, 1.0},
        text_color = options.text_color or {1, 1, 1, 1},

        -- State
        visible = true,
        enabled = true,
        hovered = false,
        pressed = false,

        -- Touch tracking
        touch_id = nil,

        -- Charge system
        charge = 0,
        charge_max = options.charge_max or 1.0,  -- 1 second default
        charging = false,

        -- Dependencies (set externally)
        display = nil,  -- engine.display
    }

    setmetatable(instance, { __index = self })
    return instance
end

-- Initialize with display reference
function skip_button:init(display)
    self.display = display
    self:calculatePosition()
end

-- Calculate position based on virtual screen size
function skip_button:calculatePosition()
    if not self.display then return end

    local vw, vh = self.display:GetVirtualDimensions()

    -- Default position: bottom-right corner
    if not self.x then
        self.x = vw - self.width - self.padding_x
    end
    if not self.y then
        self.y = vh - self.height - self.padding_y
    end
end

-- Check if point is inside button (virtual coordinates)
function skip_button:isInside(vx, vy)
    return vx >= self.x and vx <= self.x + self.width and
           vy >= self.y and vy <= self.y + self.height
end

-- Update (for charge system)
function skip_button:update(dt)
    if self.pressed then
        -- Charge when pressed
        self.charging = true
        self.charge = math.min(self.charge_max, self.charge + dt)
    else
        -- Decay charge when not pressed
        self.charging = false
        self.charge = math.max(0, self.charge - dt * 2)
    end
end

-- Check if fully charged
function skip_button:isFullyCharged()
    return self.charge >= self.charge_max
end

-- Handle touch/mouse press
function skip_button:touchPressed(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return false
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    if self:isInside(vx, vy) then
        self.pressed = true
        self.touch_id = id
        return true  -- Consumed
    end

    return false
end

-- Handle touch/mouse release
function skip_button:touchReleased(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return false
    end

    -- Only process if this touch/click started on the button
    if self.touch_id ~= id then
        dprint("[SKIP_BUTTON] Touch ID mismatch: expected " .. tostring(self.touch_id) .. ", got " .. tostring(id))
        return false
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    local was_pressed = self.pressed
    local was_fully_charged = self:isFullyCharged()
    self.pressed = false
    self.touch_id = nil

    -- Check if fully charged and released inside button
    if was_pressed and was_fully_charged and self:isInside(vx, vy) then
        dprint("[SKIP_BUTTON] Button skip triggered (fully charged)")
        self.charge = 0  -- Reset charge
        return true  -- Skip triggered!
    end

    dprint("[SKIP_BUTTON] Released without full charge or outside button area")
    return false
end

-- Handle touch/mouse move (for hover effect)
function skip_button:touchMoved(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    self.hovered = self:isInside(vx, vy)
end

-- Update hover state based on mouse position (desktop)
function skip_button:updateHover()
    if not self.visible or not self.enabled or not self.display then
        self.hovered = false
        return
    end

    local mx, my = love.mouse.getPosition()
    local vx, vy = coords:physicalToVirtual(mx, my, self.display)

    self.hovered = self:isInside(vx, vy)
end

-- Draw the button (in virtual coordinate space)
function skip_button:draw()
    if not self.visible or not self.display then
        return
    end

    -- Select background color based on state
    local bg_color = self.bg_color
    if self.hovered or self.pressed then
        bg_color = self.bg_hover_color
    end

    -- Draw background
    love.graphics.setColor(bg_color)
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height, 8, 8)

    -- Draw charge indicator (progress bar inside button)
    if self.charge > 0 then
        local charge_ratio = self.charge / self.charge_max
        local charge_width = self.width * charge_ratio

        -- Charge fill color (orange to yellow gradient)
        local r = 0.8 + charge_ratio * 0.2
        local g = 0.5 + charge_ratio * 0.5
        local b = 0.2
        love.graphics.setColor(r, g, b, 0.5)
        love.graphics.rectangle("fill", self.x, self.y, charge_width, self.height, 8, 8)
    end

    -- Draw border
    love.graphics.setColor(self.border_color)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", self.x, self.y, self.width, self.height, 8, 8)

    -- Draw text
    love.graphics.setColor(self.text_color)
    love.graphics.setFont(self.font)
    local text_width = self.font:getWidth(self.label)
    local text_height = self.font:getHeight()
    local text_x = self.x + (self.width - text_width) / 2
    local text_y = self.y + (self.height - text_height) / 2
    love.graphics.print(self.label, text_x, text_y)

    -- Reset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Show button
function skip_button:show()
    self.visible = true
end

-- Hide button
function skip_button:hide()
    self.visible = false
    self.pressed = false
    self.hovered = false
    self.touch_id = nil
end

-- Enable button
function skip_button:enable()
    self.enabled = true
end

-- Disable button
function skip_button:disable()
    self.enabled = false
    self.pressed = false
    self.hovered = false
    self.touch_id = nil
end

-- Reset button state
function skip_button:reset()
    self.pressed = false
    self.hovered = false
    self.touch_id = nil
    self.charge = 0
    self.charging = false
end

return skip_button

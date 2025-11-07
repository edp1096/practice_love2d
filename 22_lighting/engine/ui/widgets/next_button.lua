-- engine/ui/widgets/next_button.lua
-- Reusable NEXT button widget for dialogue/cutscenes (advances to next message)

local coords = require "engine.coords"

local next_button = {}

-- Create a new next button instance
function next_button:new(options)
    options = options or {}

    local instance = {
        -- Position (virtual coordinates, default: bottom-right, left of SKIP button)
        x = options.x or nil,  -- nil = auto-calculate
        y = options.y or nil,  -- nil = auto-calculate

        -- Size
        width = options.width or 100,
        height = options.height or 45,

        -- Padding from screen edges and other buttons
        padding_x = options.padding_x or 15,
        padding_y = options.padding_y or 15,
        button_spacing = options.button_spacing or 10,  -- Space between NEXT and SKIP

        -- Appearance
        label = options.label or "NEXT",
        font = options.font or love.graphics.newFont(16),

        -- Colors
        bg_color = options.bg_color or {0.2, 0.4, 0.2, 0.8},  -- Greenish
        bg_hover_color = options.bg_hover_color or {0.3, 0.5, 0.3, 0.9},
        border_color = options.border_color or {0.4, 0.8, 0.4, 1.0},
        text_color = options.text_color or {1, 1, 1, 1},

        -- State
        visible = true,
        enabled = true,
        hovered = false,
        pressed = false,

        -- Touch tracking
        touch_id = nil,

        -- Dependencies (set externally)
        display = nil,  -- engine.display
    }

    setmetatable(instance, { __index = self })
    return instance
end

-- Initialize with display reference
function next_button:init(display)
    self.display = display
    self:calculatePosition()
end

-- Calculate position based on virtual screen size and SKIP button
function next_button:calculatePosition(skip_button)
    if not self.display then return end

    local vw, vh = self.display:GetVirtualDimensions()

    -- Default position: bottom-right corner, left of SKIP button
    if not self.x then
        if skip_button then
            -- Position left of SKIP button
            self.x = skip_button.x - self.width - self.button_spacing
        else
            -- Fallback: position as if SKIP exists
            local skip_width = 100
            self.x = vw - skip_width - self.padding_x - self.width - self.button_spacing
        end
    end
    if not self.y then
        self.y = vh - self.height - self.padding_y
    end
end

-- Check if point is inside button (virtual coordinates)
function next_button:isInside(vx, vy)
    return vx >= self.x and vx <= self.x + self.width and
           vy >= self.y and vy <= self.y + self.height
end

-- Handle touch/mouse press
function next_button:touchPressed(id, x, y)
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
function next_button:touchReleased(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return false
    end

    -- Only process if this touch/click started on the button
    if self.touch_id ~= id then
        dprint("[NEXT_BUTTON] Touch ID mismatch: expected " .. tostring(self.touch_id) .. ", got " .. tostring(id))
        return false
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    local was_pressed = self.pressed
    self.pressed = false
    self.touch_id = nil

    -- Check if released inside button (complete click)
    if was_pressed and self:isInside(vx, vy) then
        dprint("[NEXT_BUTTON] Button clicked successfully")
        return true  -- Button clicked!
    end

    dprint("[NEXT_BUTTON] Released outside button area")
    return false
end

-- Handle touch/mouse move (for hover effect)
function next_button:touchMoved(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    self.hovered = self:isInside(vx, vy)
end

-- Update hover state based on mouse position (desktop)
function next_button:updateHover()
    if not self.visible or not self.enabled or not self.display then
        self.hovered = false
        return
    end

    local mx, my = love.mouse.getPosition()
    local vx, vy = coords:physicalToVirtual(mx, my, self.display)

    self.hovered = self:isInside(vx, vy)
end

-- Draw the button (in virtual coordinate space)
function next_button:draw()
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
function next_button:show()
    self.visible = true
end

-- Hide button
function next_button:hide()
    self.visible = false
    self.pressed = false
    self.hovered = false
    self.touch_id = nil
end

-- Enable button
function next_button:enable()
    self.enabled = true
end

-- Disable button
function next_button:disable()
    self.enabled = false
    self.pressed = false
    self.hovered = false
    self.touch_id = nil
end

-- Reset button state
function next_button:reset()
    self.pressed = false
    self.hovered = false
    self.touch_id = nil
end

return next_button

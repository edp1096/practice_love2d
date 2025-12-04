-- engine/ui/widgets/button/base.lua
-- Base button widget class with common functionality

local coords = require "engine.core.coords"
local text_ui = require "engine.utils.text"
local input = require "engine.core.input"
local button_icons = require "engine.utils.button_icons"

local BaseButton = {}
BaseButton.__index = BaseButton

-- Create a new button instance
function BaseButton:new(options)
    options = options or {}

    local instance = {
        -- Position (virtual coordinates)
        x = options.x or nil,
        y = options.y or nil,

        -- Size
        width = options.width or 100,
        height = options.height or 50,

        -- Padding from screen edges
        padding_x = options.padding_x or 20,
        padding_y = options.padding_y or 20,

        -- Appearance
        label = options.label or "BUTTON",
        font = options.font or love.graphics.newFont(16),

        -- Colors
        bg_color = options.bg_color or {0.2, 0.2, 0.2, 0.8},
        bg_hover_color = options.bg_hover_color or {0.3, 0.3, 0.3, 0.9},
        border_color = options.border_color or {0.6, 0.6, 0.6, 1.0},
        text_color = options.text_color or {1, 1, 1, 1},

        -- State
        visible = true,
        enabled = true,
        is_hovered = false,
        is_pressed = false,

        -- Touch tracking
        touch_id = nil,

        -- Dependencies (set externally)
        display = nil,  -- engine.display
    }

    setmetatable(instance, self)
    return instance
end

-- Initialize with display reference
function BaseButton:init(display)
    self.display = display
    self:calculatePosition()
end

-- Calculate position based on virtual screen size (override in subclass if needed)
function BaseButton:calculatePosition()
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
function BaseButton:isInside(vx, vy)
    return vx >= self.x and vx <= self.x + self.width and
           vy >= self.y and vy <= self.y + self.height
end

-- Update (override in subclass if needed)
function BaseButton:update(dt)
    -- Base implementation does nothing
end

-- Handle touch/mouse press
function BaseButton:touchPressed(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return false
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    if self:isInside(vx, vy) then
        self.is_pressed = true
        self.touch_id = id
        return true  -- Consumed
    end

    return false
end

-- Handle touch/mouse release
function BaseButton:touchReleased(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return false
    end

    -- Only process if this touch/click started on the button
    if self.touch_id ~= id then
        return false
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    local was_pressed = self.is_pressed
    self.is_pressed = false
    self.touch_id = nil

    -- Check if released inside button (complete click)
    if was_pressed and self:isInside(vx, vy) then
        return true  -- Button clicked!
    end

    return false
end

-- Handle touch/mouse move (for hover effect)
function BaseButton:touchMoved(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return
    end

    -- Convert physical to virtual coordinates
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    self.is_hovered = self:isInside(vx, vy)
end

-- Update hover state based on mouse position (desktop)
function BaseButton:updateHover()
    if not self.visible or not self.enabled or not self.display then
        self.is_hovered = false
        return
    end

    local mx, my = love.mouse.getPosition()
    local vx, vy = coords:physicalToVirtual(mx, my, self.display)

    self.is_hovered = self:isInside(vx, vy)
end

-- Draw the button (override in subclass for custom rendering)
function BaseButton:draw()
    if not self.visible or not self.display then
        return
    end

    -- Select background color based on state
    local bg_color = self.bg_color
    if self.is_hovered or self.is_pressed then
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
    local text_width = self.font:getWidth(self.label)
    local text_height = self.font:getHeight()
    local text_x = self.x + (self.width - text_width) / 2
    local text_y = self.y + (self.height - text_height) / 2
    text_ui:draw(self.label, text_x, text_y, self.text_color, self.font)

    -- Reset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Show button
function BaseButton:show()
    self.visible = true
end

-- Hide button
function BaseButton:hide()
    self.visible = false
    self.is_pressed = false
    self.is_hovered = false
    self.touch_id = nil
end

-- Enable button
function BaseButton:enable()
    self.enabled = true
end

-- Disable button
function BaseButton:disable()
    self.enabled = false
    self.is_pressed = false
    self.is_hovered = false
    self.touch_id = nil
end

-- Reset button state
function BaseButton:reset()
    self.is_pressed = false
    self.is_hovered = false
    self.touch_id = nil
end

-- Draw label with optional gamepad prompt
-- @param action: input action name (e.g., "menu_back", "menu_select")
-- @param ps_icon: PlayStation icon name (e.g., "circle", "cross")
function BaseButton:drawLabelWithPrompt(action, ps_icon)
    local virtual_gamepad = input.virtual_gamepad
    local is_virtual_active = virtual_gamepad and virtual_gamepad.enabled

    local label_width = self.font:getWidth(self.label)
    local text_height = self.font:getHeight()
    local text_y = self.y + (self.height - text_height) / 2

    -- Show button prompt only for physical gamepad (not keyboard or virtual gamepad)
    if input.joystick and not is_virtual_active then
        local spacing = 8

        -- Calculate total width for centering
        local total_width
        if input.gamepad_type == "playstation" then
            total_width = label_width + spacing + 16  -- icon is 16px
        else
            local button_prompt = input:getPrompt(action) or "?"
            local prompt_text = string.format("[%s]", button_prompt)
            local prompt_width = self.font:getWidth(prompt_text)
            total_width = label_width + spacing + prompt_width
        end

        local start_x = self.x + (self.width - total_width) / 2

        -- Draw label
        text_ui:draw(self.label, start_x, text_y, self.text_color, self.font)

        -- Draw button icon/text
        local icon_x = start_x + label_width + spacing
        local icon_y = text_y + text_height / 2

        if input.gamepad_type == "playstation" then
            button_icons:drawPlayStation(icon_x + 8, icon_y, ps_icon, 16)
        else
            local button_prompt = input:getPrompt(action) or "?"
            local prompt_text = string.format("[%s]", button_prompt)
            text_ui:draw(prompt_text, icon_x, text_y, self.text_color, self.font)
        end
    else
        -- No gamepad - just draw label centered
        local text_x = self.x + (self.width - label_width) / 2
        text_ui:draw(self.label, text_x, text_y, self.text_color, self.font)
    end
end

return BaseButton

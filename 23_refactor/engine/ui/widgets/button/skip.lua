-- engine/ui/widgets/button/skip.lua
-- SKIP button widget with charge system (hold to skip)

local BaseButton = require "engine.ui.widgets.button.base"
local text_ui = require "engine.utils.text"
local input = require "engine.core.input"

local SkipButton = setmetatable({}, { __index = BaseButton })
SkipButton.__index = SkipButton

-- Create a new skip button instance
function SkipButton:new(options)
    options = options or {}

    -- Set skip-specific defaults
    options.label = options.label or "SKIP"
    options.width = options.width or 120
    options.height = options.height or 50

    -- Create base button
    local instance = BaseButton.new(self, options)

    -- Add charge system properties
    instance.charge = 0
    instance.charge_max = options.charge_max or 1.0  -- 1 second default
    instance.is_charging = false

    return instance
end

-- Update charge system
function SkipButton:update(dt)
    if self.is_pressed then
        -- Charge when pressed
        self.is_charging = true
        self.charge = math.min(self.charge_max, self.charge + dt)
    else
        -- Decay charge when not pressed
        self.is_charging = false
        self.charge = math.max(0, self.charge - dt * 2)
    end
end

-- Check if fully charged
function SkipButton:isFullyCharged()
    return self.charge >= self.charge_max
end

-- Override touchReleased to check for full charge
function SkipButton:touchReleased(id, x, y)
    if not self.visible or not self.enabled or not self.display then
        return false
    end

    -- Only process if this touch/click started on the button
    if self.touch_id ~= id then
        return false
    end

    -- Convert physical to virtual coordinates
    local coords = require "engine.core.coords"
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    local was_pressed = self.is_pressed
    local was_fully_charged = self:isFullyCharged()
    self.is_pressed = false
    self.touch_id = nil

    -- Check if fully charged and released inside button
    if was_pressed and was_fully_charged and self:isInside(vx, vy) then
        self.charge = 0  -- Reset charge
        return true  -- Skip triggered!
    end

    return false
end

-- Override draw to show charge indicator
function SkipButton:draw()
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

    -- Draw text with shortcut hint (only for physical gamepad)
    local label_text = self.label
    if input.joystick then
        local button_prompt = input:getPrompt("menu_back") or "B"
        label_text = string.format("%s [%s]", self.label, button_prompt)
    end

    local text_width = self.font:getWidth(label_text)
    local text_height = self.font:getHeight()
    local text_x = self.x + (self.width - text_width) / 2
    local text_y = self.y + (self.height - text_height) / 2
    text_ui:draw(label_text, text_x, text_y, self.text_color, self.font)

    -- Reset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Override reset to include charge
function SkipButton:reset()
    BaseButton.reset(self)
    self.charge = 0
    self.is_charging = false
end

return SkipButton

-- engine/ui/widgets/button/skip.lua
-- SKIP button widget with charge system (hold to skip)

local BaseButton = require "engine.ui.widgets.button.base"
local text_ui = require "engine.utils.text"
local input = require "engine.core.input"
local button_icons = require "engine.utils.button_icons"

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

    -- Draw text with shortcut hint (only for physical gamepad, not keyboard/virtual gamepad)
    local virtual_gamepad = input.virtual_gamepad
    local is_virtual_active = virtual_gamepad and virtual_gamepad.enabled

    -- Calculate text metrics
    local label_width = self.font:getWidth(self.label)
    local text_height = self.font:getHeight()
    local text_y = self.y + (self.height - text_height) / 2

    -- Show button prompt only for physical gamepad (not keyboard or virtual gamepad)
    if input.joystick and not is_virtual_active then
        local spacing = 8  -- Space between label and icon

        -- Calculate total width for centering
        local total_width
        if input.gamepad_type == "playstation" then
            -- PlayStation: label + spacing + icon (16px)
            total_width = label_width + spacing + 16
        else
            -- Xbox: label + spacing + "[B]" text
            local button_prompt = input:getPrompt("menu_back") or "B"
            local prompt_text = string.format("[%s]", button_prompt)
            local prompt_width = self.font:getWidth(prompt_text)
            total_width = label_width + spacing + prompt_width
        end

        -- Center the entire content (label + icon)
        local start_x = self.x + (self.width - total_width) / 2

        -- Draw label
        text_ui:draw(self.label, start_x, text_y, self.text_color, self.font)

        -- Draw button icon/text
        local icon_x = start_x + label_width + spacing
        local icon_y = text_y + text_height / 2

        if input.gamepad_type == "playstation" then
            -- Draw PlayStation circle icon (centered at icon_x + 8)
            button_icons:drawPlayStation(icon_x + 8, icon_y, "circle", 16)
        else
            -- Draw Xbox text "[B]"
            local button_prompt = input:getPrompt("menu_back") or "B"
            local prompt_text = string.format("[%s]", button_prompt)
            text_ui:draw(prompt_text, icon_x, text_y, self.text_color, self.font)
        end
    else
        -- No gamepad - just draw label centered
        local text_x = self.x + (self.width - label_width) / 2
        text_ui:draw(self.label, text_x, text_y, self.text_color, self.font)
    end

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

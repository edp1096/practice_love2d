-- engine/ui/widgets/button/next.lua
-- NEXT button widget for advancing dialogue/cutscenes

local BaseButton = require "engine.ui.widgets.button.base"
local input = require "engine.core.input"
local text_ui = require "engine.utils.text"
local button_icons = require "engine.utils.button_icons"

local NextButton = setmetatable({}, { __index = BaseButton })
NextButton.__index = NextButton

-- Create a new next button instance
function NextButton:new(options)
    options = options or {}

    -- Set next-specific defaults
    options.label = options.label or "NEXT"
    options.width = options.width or 100
    options.height = options.height or 45
    options.padding_x = options.padding_x or 15
    options.padding_y = options.padding_y or 15

    -- Next button colors (greenish)
    options.bg_color = options.bg_color or {0.2, 0.4, 0.2, 0.8}
    options.bg_hover_color = options.bg_hover_color or {0.3, 0.5, 0.3, 0.9}
    options.border_color = options.border_color or {0.4, 0.8, 0.4, 1.0}

    -- Create base button
    local instance = BaseButton.new(self, options)

    -- Add spacing for positioning relative to skip button
    instance.button_spacing = options.button_spacing

    return instance
end

-- Override calculatePosition to position left of SKIP button
function NextButton:calculatePosition(skip_button)
    if not self.display then return end

    local vw, vh = self.display:GetVirtualDimensions()

    -- Default position: bottom-right corner, left of SKIP button
    if not self.x then
        if skip_button then
            -- Position left of SKIP button
            self.x = skip_button.x - self.width - self.button_spacing
        else
            -- Fallback: position as if SKIP exists
            local skip_width = 120
            self.x = vw - skip_width - self.padding_x - self.width - self.button_spacing
        end
    end
    if not self.y then
        self.y = vh - self.height - self.padding_y
    end
end

-- Override touchReleased with logging
function NextButton:touchReleased(id, x, y)
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
    self.is_pressed = false
    self.touch_id = nil

    -- Check if released inside button (complete click)
    if was_pressed and self:isInside(vx, vy) then
        return true  -- Button clicked!
    end

    return false
end

-- Override draw to show shortcut hint
function NextButton:draw()
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
            -- Xbox: label + spacing + "[A]" text
            local button_prompt = input:getPrompt("menu_select") or "A"
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
            -- Draw PlayStation cross icon (centered at icon_x + 8)
            button_icons:drawPlayStation(icon_x + 8, icon_y, "cross", 16)
        else
            -- Draw Xbox text "[A]"
            local button_prompt = input:getPrompt("menu_select") or "A"
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

return NextButton

-- engine/ui/prompt.lua
-- Helper for drawing interaction prompts with appropriate button icons

local input = require "engine.core.input"
local text_ui = require "engine.utils.text"

local prompt = {}

-- Draw interaction prompt (button icon in circle)
-- Parameters:
--   action: action name (e.g., "interact")
--   x, y: center position
--   y_offset: vertical offset from center (default: -30)
--   color: text color (default: yellow)
function prompt:draw(action, x, y, y_offset, color)
    y_offset = y_offset or -30
    color = color or {1, 1, 0, 1}

    -- Get button prompt based on current input method
    local button_text = input:getPrompt(action)
    local text_width = love.graphics.getFont():getWidth(button_text)

    -- Draw circle
    love.graphics.setColor(1, 1, 0, 1)
    love.graphics.circle("line", x, y + y_offset, 20)

    -- Draw button text (centered)
    text_ui:draw(button_text, x - text_width / 2, y + y_offset - 5, color)
end

return prompt

-- engine/systems/prompt.lua
-- Interaction prompt system (systems layer - depends on core, utils)

local input = require "engine.core.input"
local text_ui = require "engine.utils.text"
local colors = require "engine.utils.colors"

local prompt = {}

-- Reference to dialogue system (set by main.lua)
prompt.dialogue = nil

-- Draw interaction prompt (button icon in circle)
-- Parameters:
--   action: action name (e.g., "interact")
--   x, y: center position
--   y_offset: vertical offset from center (default: -30)
--   color: text color (default: yellow)
function prompt:draw(action, x, y, y_offset, color)
    -- Hide prompt if dialogue is open
    if self.dialogue and self.dialogue:isOpen() then
        return
    end

    y_offset = y_offset or -30
    color = color or {1, 1, 0, 1}

    -- Get button prompt based on current input method
    local button_text = input:getPrompt(action)
    local font = love.graphics.getFont()
    local text_width = font:getWidth(button_text)
    local text_height = font:getHeight()

    local circle_x = x
    local circle_y = y + y_offset
    local circle_radius = 24

    -- Draw semi-transparent background circle
    colors:apply(colors.for_prompt_bg)
    love.graphics.circle("fill", circle_x, circle_y, circle_radius)

    -- Draw bright yellow outline circle
    colors:apply(colors.for_prompt_outline)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", circle_x, circle_y, circle_radius)
    love.graphics.setLineWidth(1)

    -- Draw button text with outline for better visibility
    local text_x = circle_x - text_width / 2
    local text_y = circle_y - text_height / 2

    -- Text outline (black)
    for ox = -1, 1 do
        for oy = -1, 1 do
            if ox ~= 0 or oy ~= 0 then
                text_ui:draw(button_text, text_x + ox, text_y + oy, {0, 0, 0, 0.8})
            end
        end
    end

    -- Text foreground (bright yellow)
    text_ui:draw(button_text, text_x, text_y, colors.for_prompt_outline)
end

return prompt

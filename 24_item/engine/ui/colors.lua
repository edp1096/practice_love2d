-- engine/ui/colors.lua
-- Centralized color palette for UI elements

local colors = {}

-- UI Background Colors
colors.UI_BG_DARK = {0.2, 0.2, 0.2}
colors.UI_BG_MEDIUM = {0.3, 0.3, 0.3}
colors.UI_BG_LIGHT = {0.4, 0.4, 0.4}

-- UI Border/Outline Colors
colors.UI_BORDER = {0.5, 0.5, 0.5}
colors.UI_BORDER_LIGHT = {0.6, 0.6, 0.6}

-- UI Highlight/Hover Colors
colors.UI_HIGHLIGHT = {0.8, 0.8, 1.0}
colors.UI_ACTIVE = {1, 0.9, 0}
colors.UI_HOVER = {0.6, 0.6, 0.8}

-- UI Text Colors
colors.TEXT_WHITE = {1, 1, 1}
colors.TEXT_GRAY = {0.7, 0.7, 0.7}
colors.TEXT_DARK = {0.3, 0.3, 0.3}

-- Status Colors
colors.HEALTH_FULL = {0, 1, 0}
colors.HEALTH_MID = {1, 0.8, 0}
colors.HEALTH_LOW = {1, 0, 0}
colors.ENERGY_BLUE = {0.2, 0.5, 1.0}

-- Virtual Gamepad Colors
colors.GAMEPAD_BG = {0.2, 0.2, 0.2}
colors.GAMEPAD_BORDER = {0.5, 0.5, 0.5}
colors.GAMEPAD_STICK = {0.8, 0.8, 1.0}
colors.GAMEPAD_BUTTON = {0.3, 0.3, 0.3}
colors.GAMEPAD_ACTIVE = {1, 0.9, 0}

-- Debug Colors
colors.DEBUG_GRID = {0.3, 0.3, 0.3}
colors.DEBUG_COLLIDER = {1, 0, 0}
colors.DEBUG_GROUND = {0, 1, 0}
colors.DEBUG_TEXT = {1, 1, 0}

-- Helper function to apply color with alpha
function colors:apply(color, alpha)
    alpha = alpha or 1.0
    love.graphics.setColor(color[1], color[2], color[3], alpha)
end

-- Helper function to reset to white
function colors:reset()
    love.graphics.setColor(1, 1, 1, 1)
end

return colors

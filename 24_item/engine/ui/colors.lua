-- engine/ui/colors.lua
-- Centralized color palette for UI elements

local colors = {}

-- ========================================
-- INVENTORY UI COLORS
-- ========================================

-- Item borders and cursor (3-tier visual hierarchy)
colors.ITEM_BORDER = {0.3, 0.5, 0.2, 0.8}        -- Olive drab (subtle)
colors.ITEM_SELECTED = {0.5, 0.8, 1, 1}          -- Blue (medium emphasis)
colors.GAMEPAD_CURSOR = {1, 1, 0, 0.8}           -- Yellow (strong emphasis)

-- Border widths
colors.ITEM_BORDER_WIDTH = 1
colors.ITEM_SELECTED_WIDTH = 2
colors.GAMEPAD_CURSOR_WIDTH = 3

-- Inventory panel
colors.INVENTORY_BG = {0.15, 0.15, 0.2, 0.95}
colors.INVENTORY_BORDER = {0.3, 0.3, 0.4, 1}

-- Item status colors
colors.ITEM_EQUIPMENT = {0.8, 0.7, 1, 1}         -- Purple
colors.ITEM_USABLE = {0.3, 1, 0.3, 1}            -- Green
colors.ITEM_SMALL_POTION = {0.5, 1, 0.5, 1}      -- Light green
colors.ITEM_LARGE_POTION = {0.3, 1, 0.8, 1}      -- Cyan

-- Placement preview
colors.PLACEMENT_VALID = {0.3, 1, 0.3, 0.3}      -- Green
colors.PLACEMENT_INVALID = {1, 0.3, 0.3, 0.3}    -- Red

-- ========================================
-- COMMON TEXT COLORS
-- ========================================

colors.TEXT_WHITE = {1, 1, 1, 1}
colors.TEXT_LIGHT = {0.9, 0.9, 0.9, 1}
colors.TEXT_GRAY = {0.8, 0.8, 0.8, 1}
colors.TEXT_MID_GRAY = {0.7, 0.7, 0.7, 1}
colors.TEXT_DARK_GRAY = {0.6, 0.6, 0.6, 1}
colors.TEXT_DIM = {0.5, 0.5, 0.5, 1}
colors.TEXT_HINT = {0.6, 0.8, 1, 1}              -- Blue hint

-- ========================================
-- MENU & DIALOG COLORS
-- ========================================

-- Dialog backgrounds
colors.DIALOG_OVERLAY = {0, 0, 0, 0.85}
colors.DIALOG_DARK = {0, 0, 0, 0.9}

-- Menu highlights
colors.MENU_SELECTED = {1, 1, 0, 1}              -- Yellow
colors.MENU_CONTROLLER_INFO = {0.3, 0.8, 0.3, 1} -- Green

-- ========================================
-- BUTTON COLORS
-- ========================================

-- Delete/Danger buttons
colors.BUTTON_DELETE_NORMAL = {0.5, 0.2, 0.2, 0.7}
colors.BUTTON_DELETE_SELECTED = {0.8, 0.2, 0.2, 0.9}
colors.BUTTON_DELETE_BORDER_NORMAL = {0.7, 0.3, 0.3, 1}
colors.BUTTON_DELETE_BORDER_SELECTED = {1, 0.3, 0.3, 1}

-- Action buttons
colors.BUTTON_ACTION_NORMAL = {0.3, 0.3, 0.3, 0.7}
colors.BUTTON_ACTION_SELECTED = {0.4, 0.4, 0.4, 0.9}
colors.BUTTON_ACTION_BORDER_NORMAL = {0.5, 0.5, 0.5, 1}
colors.BUTTON_ACTION_BORDER_SELECTED = {0.7, 0.7, 0.7, 1}

-- Settings arrows
colors.SETTINGS_ARROW = {0.5, 0.5, 1, 1}

-- ========================================
-- PANEL/BACKGROUND COLORS
-- ========================================

colors.PANEL_BG_DARK = {0.2, 0.2, 0.2}
colors.PANEL_BG_MEDIUM = {0.3, 0.3, 0.3}
colors.PANEL_BG_LIGHT = {0.4, 0.4, 0.4}
colors.PANEL_BORDER = {0.5, 0.5, 0.5}

-- ========================================
-- STATUS & HEALTH COLORS
-- ========================================

colors.HEALTH_FULL = {0, 1, 0}
colors.HEALTH_MID = {1, 0.8, 0}
colors.HEALTH_LOW = {1, 0, 0}
colors.ENERGY_BLUE = {0.2, 0.5, 1.0}

-- ========================================
-- VIRTUAL GAMEPAD COLORS
-- ========================================

colors.GAMEPAD_BG = {0.2, 0.2, 0.2}
colors.GAMEPAD_BORDER = {0.5, 0.5, 0.5}
colors.GAMEPAD_STICK = {0.8, 0.8, 1.0}
colors.GAMEPAD_BUTTON = {0.3, 0.3, 0.3}
colors.GAMEPAD_ACTIVE = {1, 0.9, 0}

-- ========================================
-- DEBUG COLORS
-- ========================================

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

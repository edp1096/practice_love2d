-- engine/ui/colors.lua
-- Centralized color palette for UI elements

local colors = {}

-- ========================================
-- PART 1: COLOR PALETTE (Pure color names)
-- ========================================

-- Neutrals
colors.WHITE = {1, 1, 1, 1}
colors.LIGHT_GRAY = {0.9, 0.9, 0.9, 1}
colors.GRAY = {0.8, 0.8, 0.8, 1}
colors.MID_GRAY = {0.7, 0.7, 0.7, 1}
colors.DARK_GRAY = {0.6, 0.6, 0.6, 1}
colors.DIM_GRAY = {0.5, 0.5, 0.5, 1}
colors.CHARCOAL = {0.3, 0.3, 0.3}
colors.DARK_CHARCOAL = {0.2, 0.2, 0.2}

-- Blues
colors.SKY_BLUE = {0.5, 0.8, 1, 1}
colors.LIGHT_BLUE_HINT = {0.6, 0.8, 1, 1}
colors.MEDIUM_BLUE = {0.3, 0.5, 0.8, 0.9}
colors.NAVY_BLUE = {0.15, 0.15, 0.2, 0.95}
colors.BLUE_GRAY = {0.3, 0.3, 0.4, 1}
colors.SLATE_BLUE = {0.5, 0.5, 1, 1}
colors.BRIGHT_CYAN_BLUE = {0.2, 0.5, 1.0}

-- Greens
colors.OLIVE_DRAB = {0.3, 0.5, 0.2, 0.8}
colors.BRIGHT_GREEN = {0.3, 1, 0.3, 1}
colors.LIGHT_GREEN = {0.5, 1, 0.5, 1}
colors.CYAN_GREEN = {0.3, 1, 0.8, 1}
colors.PALE_GREEN = {0.3, 0.8, 0.3, 1}
colors.FULL_GREEN = {0, 1, 0}

-- Yellows
colors.BRIGHT_YELLOW = {1, 1, 0, 1}
colors.BRIGHT_YELLOW_ALPHA = {1, 1, 0, 0.8}
colors.GOLDEN_YELLOW = {1, 0.9, 0}
colors.AMBER = {1, 0.8, 0}

-- Reds
colors.DARK_RED = {0.5, 0.2, 0.2, 0.7}
colors.BRIGHT_RED = {0.8, 0.2, 0.2, 0.9}
colors.CRIMSON = {0.7, 0.3, 0.3, 1}
colors.BRIGHT_CRIMSON = {1, 0.3, 0.3, 1}
colors.FULL_RED = {1, 0, 0}

-- Purples
colors.LIGHT_PURPLE = {0.8, 0.7, 1, 1}

-- Transparent/Alpha variations
colors.LIGHT_GREEN_ALPHA = {0.3, 1, 0.3, 0.3}
colors.LIGHT_RED_ALPHA = {1, 0.3, 0.3, 0.3}
colors.BLACK_OVERLAY = {0, 0, 0, 0.85}
colors.BLACK_DARK_OVERLAY = {0, 0, 0, 0.9}
colors.DARK_BLUE_TRANSPARENT = {0.3, 0.3, 0.4, 0.8}
colors.CHARCOAL_TRANSPARENT = {0.3, 0.3, 0.3, 0.7}
colors.CHARCOAL_SELECTED = {0.4, 0.4, 0.4, 0.9}

-- Special UI colors
colors.LIGHT_CYAN_BLUE = {0.8, 0.8, 1.0}

-- ========================================
-- PART 2: SEMANTIC MAPPING (UI purpose)
-- ========================================

-- Inventory UI
colors.for_item_border = colors.OLIVE_DRAB
colors.for_item_selected = colors.SKY_BLUE
colors.for_gamepad_cursor = colors.BRIGHT_YELLOW_ALPHA
colors.for_inventory_bg = colors.NAVY_BLUE
colors.for_inventory_border = colors.BLUE_GRAY
colors.for_item_equipment = colors.LIGHT_PURPLE
colors.for_item_usable = colors.BRIGHT_GREEN
colors.for_placement_valid = colors.LIGHT_GREEN_ALPHA
colors.for_placement_invalid = colors.LIGHT_RED_ALPHA

-- Text colors
colors.for_text_normal = colors.WHITE
colors.for_text_light = colors.LIGHT_GRAY
colors.for_text_gray = colors.GRAY
colors.for_text_mid_gray = colors.MID_GRAY
colors.for_text_dark_gray = colors.DARK_GRAY
colors.for_text_dim = colors.DIM_GRAY
colors.for_text_hint = colors.LIGHT_BLUE_HINT

-- Menu & Dialog
colors.for_dialog_overlay = colors.BLACK_OVERLAY
colors.for_dialog_dark = colors.BLACK_DARK_OVERLAY
colors.for_menu_selected = colors.BRIGHT_YELLOW
colors.for_menu_controller_info = colors.PALE_GREEN

-- Buttons
colors.for_button_delete_normal = colors.DARK_RED
colors.for_button_delete_selected = colors.BRIGHT_RED
colors.for_button_delete_border_normal = colors.CRIMSON
colors.for_button_delete_border_selected = colors.BRIGHT_CRIMSON
colors.for_button_action_normal = colors.CHARCOAL_TRANSPARENT
colors.for_button_action_selected = colors.CHARCOAL_SELECTED
colors.for_button_action_border_normal = colors.DIM_GRAY
colors.for_button_action_border_selected = colors.MID_GRAY
colors.for_button_selected_bg = colors.MEDIUM_BLUE
colors.for_button_selected_border = colors.SKY_BLUE
colors.for_button_hover_bg = colors.DARK_BLUE_TRANSPARENT
colors.for_button_hover_border = colors.BRIGHT_YELLOW_ALPHA
colors.for_button_normal_bg = colors.DARK_BLUE_TRANSPARENT
colors.for_button_normal_border = colors.BLUE_GRAY

-- Settings
colors.for_settings_arrow = colors.SLATE_BLUE

-- Panels
colors.for_panel_bg_dark = colors.DARK_CHARCOAL
colors.for_panel_bg_medium = colors.CHARCOAL
colors.for_panel_bg_light = colors.BLUE_GRAY
colors.for_panel_border = colors.DIM_GRAY

-- Status & Health
colors.for_health_full = colors.FULL_GREEN
colors.for_health_mid = colors.AMBER
colors.for_health_low = colors.FULL_RED
colors.for_energy = colors.BRIGHT_CYAN_BLUE

-- Virtual Gamepad
colors.for_gamepad_bg = colors.DARK_CHARCOAL
colors.for_gamepad_border = colors.DIM_GRAY
colors.for_gamepad_stick = colors.LIGHT_CYAN_BLUE
colors.for_gamepad_button = colors.CHARCOAL
colors.for_gamepad_active = colors.GOLDEN_YELLOW

-- Debug
colors.for_debug_grid = colors.CHARCOAL
colors.for_debug_collider = colors.FULL_RED
colors.for_debug_ground = colors.FULL_GREEN
colors.for_debug_text = colors.BRIGHT_YELLOW

-- ========================================
-- PART 3: CONSTANTS
-- ========================================

-- Border widths
colors.BORDER_WIDTH_THIN = 1
colors.BORDER_WIDTH_MEDIUM = 2
colors.BORDER_WIDTH_THICK = 3

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

-- engine/ui/colors.lua
-- Centralized color palette for UI elements

local colors = {}

-- ========================================
-- PART 1: COLOR PALETTE (Pure color names)
-- ========================================

-- Neutrals
colors.BLACK = {0, 0, 0, 1}
colors.WHITE = {1, 1, 1, 1}
colors.LIGHT_GRAY = {0.9, 0.9, 0.9, 1}
colors.GRAY = {0.8, 0.8, 0.8, 1}
colors.MID_GRAY = {0.7, 0.7, 0.7, 1}
colors.DARK_GRAY = {0.6, 0.6, 0.6, 1}
colors.DIM_GRAY = {0.5, 0.5, 0.5, 1}
colors.MEDIUM_GRAY = {0.4, 0.4, 0.4, 1}
colors.CHARCOAL = {0.3, 0.3, 0.3}
colors.DARK_CHARCOAL = {0.2, 0.2, 0.2}
colors.DARK_CHARCOAL_80 = {0.2, 0.2, 0.2, 0.8}

-- Blues
colors.SKY_BLUE = {0.5, 0.8, 1, 1}
colors.LIGHT_BLUE_HINT = {0.6, 0.8, 1, 1}
colors.MEDIUM_BLUE = {0.3, 0.5, 0.8, 0.9}
colors.DIALOGUE_BLUE = {0.3, 0.6, 0.9, 0.9}
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
colors.PASTEL_YELLOW = {1, 1, 0.5, 1}
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
colors.BLACK_80 = {0, 0, 0, 0.8}
colors.DARK_BLUE_TRANSPARENT = {0.3, 0.3, 0.4, 0.8}
colors.CHARCOAL_TRANSPARENT = {0.3, 0.3, 0.3, 0.7}
colors.CHARCOAL_SELECTED = {0.4, 0.4, 0.4, 0.9}
colors.DIM_GRAY_ALPHA = {0.5, 0.5, 0.5, 0.7}

-- Special UI colors
colors.LIGHT_CYAN_BLUE = {0.8, 0.8, 1.0}

-- Minimap specific
colors.DARK_GREEN_MID = {0.3, 0.7, 0.3}
colors.DARK_GREEN_BRIGHT = {0.5, 0.9, 0.5}
colors.DARK_GREEN_DIM = {0.3, 0.6, 0.3}
colors.DARK_GREEN_SHADOW = {0.08, 0.25, 0.08}
colors.DARK_CHARCOAL_OUTLINE = {0.15, 0.15, 0.15, 1}
colors.LIME_GREEN_TRANSPARENT = {0.5, 1, 0.5, 0.6}
colors.NEON_GREEN_OUTLINE = {0.2, 1, 0.3}
colors.RED_OUTLINE = {1, 0.2, 0.2}
colors.BLACK_75 = {0, 0, 0, 0.75}
colors.CHARCOAL_90 = {0.3, 0.3, 0.3, 0.9}

-- HUD specific
colors.BLACK_50 = {0, 0, 0, 0.5}
colors.BLACK_70 = {0, 0, 0, 0.7}
colors.MID_GRAY_TEXT = {0.7, 0.7, 0.7, 1}
colors.PERFECT_PARRY_YELLOW = {1, 1, 0}
colors.PARRY_BLUE = {0.5, 0.8, 1}
colors.SLOW_MOTION_BLUE = {0.2, 0.4, 0.6}

-- Quickslot specific (moved below, using existing colors)

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
colors.for_item_unusable = colors.BRIGHT_CRIMSON
colors.for_placement_valid = colors.LIGHT_GREEN_ALPHA
colors.for_placement_invalid = colors.LIGHT_RED_ALPHA
colors.for_equipment_icon_fallback = colors.PASTEL_YELLOW

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
colors.for_debug_panel_bg = colors.BLACK_50

-- Minimap
colors.for_minimap_bg = colors.BLACK_75
colors.for_minimap_border = colors.CHARCOAL_90
colors.for_minimap_portal = colors.LIME_GREEN_TRANSPARENT
colors.for_minimap_player_mid = colors.DARK_GREEN_MID
colors.for_minimap_player_bright = colors.DARK_GREEN_BRIGHT
colors.for_minimap_player_dim = colors.DARK_GREEN_DIM
colors.for_minimap_player_shadow = colors.DARK_GREEN_SHADOW
colors.for_minimap_player_outline = colors.DARK_CHARCOAL_OUTLINE
colors.for_minimap_npc_outline = colors.NEON_GREEN_OUTLINE
colors.for_minimap_enemy_outline = colors.RED_OUTLINE

-- HUD
colors.for_hud_cooldown_bg = colors.BLACK_70
colors.for_hud_text_dim = colors.MID_GRAY_TEXT
colors.for_hud_parry_perfect = colors.PERFECT_PARRY_YELLOW
colors.for_hud_parry_normal = colors.PARRY_BLUE
colors.for_hud_slow_motion = colors.SLOW_MOTION_BLUE

-- Quickslots
colors.for_quickslot_bg = colors.DARK_CHARCOAL_80
colors.for_quickslot_border = colors.DARK_GRAY
colors.for_quickslot_selected = colors.BRIGHT_YELLOW
colors.for_quickslot_unusable = colors.DIM_GRAY_ALPHA

-- Dialogue System
colors.for_dialogue_bg = colors.BLACK_80
colors.for_dialogue_text = colors.WHITE
colors.for_dialogue_speaker = colors.WHITE
colors.for_dialogue_page_indicator = colors.MID_GRAY
colors.for_dialogue_choice_selected_bg = colors.DIALOGUE_BLUE
colors.for_dialogue_choice_normal_bg = colors.DARK_CHARCOAL_80
colors.for_dialogue_choice_selected_border = colors.SKY_BLUE
colors.for_dialogue_choice_normal_border = colors.MEDIUM_GRAY
colors.for_dialogue_choice_text_normal = colors.WHITE
colors.for_dialogue_choice_text_visited = colors.MEDIUM_GRAY

-- ========================================
-- PART 3: CONSTANTS
-- ========================================

-- Border widths
colors.BORDER_WIDTH_THIN = 1
colors.BORDER_WIDTH_MEDIUM = 2
colors.BORDER_WIDTH_THICK = 3

-- ========================================
-- PART 4: HELPER FUNCTIONS
-- ========================================

-- Apply color with optional alpha override
function colors:apply(color, alpha)
    alpha = alpha or color[4] or 1.0
    love.graphics.setColor(color[1], color[2], color[3], alpha)
end

-- Create new color table with overridden alpha
function colors:withAlpha(color, alpha)
    return {color[1], color[2], color[3], alpha}
end

-- Unpack RGB only (for cases where alpha is separate)
function colors:unpackRGB(color)
    return color[1], color[2], color[3]
end

-- Unpack RGBA with optional alpha override
function colors:unpackRGBA(color, alpha)
    alpha = alpha or color[4] or 1.0
    return color[1], color[2], color[3], alpha
end

-- Get RGBA values for mesh vertices (returns 4 values)
function colors:toVertex(color, alpha)
    alpha = alpha or color[4] or 1.0
    return color[1], color[2], color[3], alpha
end

-- Reset to white
function colors:reset()
    love.graphics.setColor(1, 1, 1, 1)
end

return colors

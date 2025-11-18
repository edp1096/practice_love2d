-- engine/ui/menu/helpers.lua
-- Common UI utilities for menu scenes to eliminate code duplication

local display = require "engine.core.display"
local input = require "engine.core.input"
local sound = require "engine.core.sound"
local fonts = require "engine.utils.fonts"
local text_ui = require "engine.utils.text"
local colors = require "engine.utils.colors"

local helpers = {}

-- Fallback fonts for confirmation dialogs (lazy-loaded)
helpers.fallback_title_font = nil
helpers.fallback_hint_font = nil
helpers.fallback_option_font = nil

-- Create standard menu layout configuration
function helpers.createMenuLayout(vh)
    return {
        title_y = vh * 0.18,
        options_start_y = vh * 0.38,
        option_spacing = 52,
        hint_y = vh - 30
    }
end

-- Create standard fonts for menu scenes
-- Returns references to centralized font manager
function helpers.createMenuFonts()
    return {
        title = fonts.title_large,
        option = fonts.option,
        hint = fonts.hint,
        label = fonts.option,
        info = fonts.info
    }
end

-- Draw menu title
function helpers.drawTitle(text, font, y, width, color)
    color = color or { 1, 1, 1, 1 }
    text_ui:drawCentered(text, y, width, color, font)
end

-- Draw menu options with selection highlight
function helpers.drawOptions(options, selected, mouse_over, font, layout, width)
    for i, option in ipairs(options) do
        local y = layout.options_start_y + (i - 1) * layout.option_spacing
        local is_selected = (i == selected)
        local display_text = is_selected and ("> " .. option) or option

        text_ui:drawOptionCentered(display_text, y, width, is_selected, font)
    end
end

-- Update mouse-over detection for menu options
function helpers.updateMouseOver(options, layout, width, font)
    local vmx, vmy = display:GetVirtualMousePosition()
    love.graphics.setFont(font)

    for i, option in ipairs(options) do
        local y = layout.options_start_y + (i - 1) * layout.option_spacing
        local text_width = font:getWidth(option)
        local text_height = font:getHeight()
        local x = (width - text_width) / 2
        local padding = 15

        if vmx >= x - padding and vmx <= x + text_width + padding and
            vmy >= y - padding and vmy <= y + text_height + padding then
            return i
        end
    end

    return 0
end

-- Draw control hints at bottom of screen
function helpers.drawControlHints(font, layout, width, custom_text)
    local hint_text
    if custom_text then
        hint_text = custom_text
    else
        -- Always show version instead of control hints
        hint_text = "v" .. (APP_CONFIG.version or "0.0.1")
    end

    text_ui:drawCentered(hint_text, layout.hint_y - 10, width, colors.for_text_dim, font)
end

-- Handle keyboard navigation (returns result table with action and new_selection)
function helpers.handleKeyboardNav(key, current_selection, option_count)
    if input:wasPressed("menu_up", "keyboard", key) then
        local new_sel = current_selection - 1
        if new_sel < 1 then new_sel = option_count end
        sound:playSFX("menu", "navigate")
        return { action = "navigate", new_selection = new_sel }
    elseif input:wasPressed("menu_down", "keyboard", key) then
        local new_sel = current_selection + 1
        if new_sel > option_count then new_sel = 1 end
        sound:playSFX("menu", "navigate")
        return { action = "navigate", new_selection = new_sel }
    elseif input:wasPressed("menu_select", "keyboard", key) then
        sound:playSFX("menu", "select")
        return { action = "select" }
    elseif input:wasPressed("menu_back", "keyboard", key) then
        return { action = "back" }
    end

    return { action = "none" }
end

-- Handle gamepad navigation (returns result table with action and new_selection)
function helpers.handleGamepadNav(button, current_selection, option_count)
    if input:wasPressed("menu_up", "gamepad", button) then
        local new_sel = current_selection - 1
        if new_sel < 1 then new_sel = option_count end
        sound:playSFX("menu", "navigate")
        return { action = "navigate", new_selection = new_sel }
    elseif input:wasPressed("menu_down", "gamepad", button) then
        local new_sel = current_selection + 1
        if new_sel > option_count then new_sel = 1 end
        sound:playSFX("menu", "navigate")
        return { action = "navigate", new_selection = new_sel }
    elseif input:wasPressed("menu_select", "gamepad", button) then
        sound:playSFX("menu", "select")
        return { action = "select" }
    elseif input:wasPressed("menu_back", "gamepad", button) then
        sound:playSFX("menu", "back")
        return { action = "back" }
    end

    return { action = "none" }
end

-- Handle mouse selection (returns selected index or nil)
function helpers.handleMouseSelection(button, mouse_over)
    if button == 1 and mouse_over > 0 then
        sound:playSFX("menu", "select")
        return mouse_over
    end
    return nil
end

-- Draw semi-transparent overlay (for pause/settings menus)
function helpers.drawOverlay(width, height, alpha)
    alpha = alpha or 0.7
    colors:apply(colors.BLACK, alpha)
    love.graphics.rectangle("fill", 0, 0, width, height)
end

-- Draw confirmation dialog (Yes/No)
function helpers.drawConfirmDialog(title, subtitle, button_labels, selected, mouse_over, fonts, width, height)
    button_labels = button_labels or { "No", "Yes" }

    -- Dark overlay
    colors:apply(colors.for_dialog_overlay)
    love.graphics.rectangle("fill", 0, 0, width, height)

    -- Title
    local title_font = fonts.title
    if not title_font then
        if not helpers.fallback_title_font then
            helpers.fallback_title_font = love.graphics.newFont(20)
        end
        title_font = helpers.fallback_title_font
    end
    text_ui:drawCentered(title, height / 2 - 60, width, {1, 0.3, 0.3, 1}, title_font)

    -- Subtitle
    if subtitle then
        local hint_font = fonts.hint
        if not hint_font then
            if not helpers.fallback_hint_font then
                helpers.fallback_hint_font = love.graphics.newFont(14)
            end
            hint_font = helpers.fallback_hint_font
        end
        text_ui:drawCentered(subtitle, height / 2 - 20, width, colors.for_text_light, hint_font)
    end

    -- Buttons
    local button_y = height / 2 + 60
    local button_width = 120
    local button_height = 50
    local button_spacing = 40

    for i = 1, #button_labels do
        local button_x = width / 2 - (#button_labels * button_width + (#button_labels - 1) * button_spacing) / 2 +
            (i - 1) * (button_width + button_spacing)
        local is_selected = (i == selected)

        -- Button background
        if i == 2 then -- Yes button (dangerous action)
            colors:apply(is_selected and colors.for_button_delete_selected or colors.for_button_delete_normal)
        else           -- No button (safe action)
            colors:apply(is_selected and colors.for_button_action_selected or colors.for_button_action_normal)
        end
        love.graphics.rectangle("fill", button_x, button_y, button_width, button_height)

        -- Button border
        if i == 2 then
            colors:apply(is_selected and colors.for_button_delete_border_selected or colors.for_button_delete_border_normal)
        else
            colors:apply(is_selected and colors.for_button_action_border_selected or colors.for_button_action_border_normal)
        end
        love.graphics.rectangle("line", button_x, button_y, button_width, button_height)

        -- Button text
        local option_font = fonts.option
        if not option_font then
            if not helpers.fallback_option_font then
                helpers.fallback_option_font = love.graphics.newFont(24)
            end
            option_font = helpers.fallback_option_font
        end
        love.graphics.setFont(option_font)
        colors:apply(is_selected and colors.for_text_normal or colors.for_text_light)
        love.graphics.printf(button_labels[i], button_x, button_y + 12, button_width, "center")
    end

    colors:reset()
end

-- Update mouse-over for confirmation dialog buttons
function helpers.updateConfirmMouseOver(width, height, button_count)
    local vmx, vmy = display:GetVirtualMousePosition()

    local button_y = height / 2 + 60
    local button_width = 120
    local button_height = 50
    local button_spacing = 40

    for i = 1, button_count do
        local button_x = width / 2 - (button_count * button_width + (button_count - 1) * button_spacing) / 2 +
            (i - 1) * (button_width + button_spacing)

        if vmx >= button_x and vmx <= button_x + button_width and
            vmy >= button_y and vmy <= button_y + button_height then
            return i
        end
    end

    return 0
end

-- Handle confirmation dialog navigation
function helpers.handleConfirmNav(key_or_button, source, current_selection, button_count)
    if source == "keyboard" then
        if input:wasPressed("menu_left", "keyboard", key_or_button) then
            return math.max(1, current_selection - 1)
        elseif input:wasPressed("menu_right", "keyboard", key_or_button) then
            return math.min(button_count, current_selection + 1)
        elseif input:wasPressed("menu_select", "keyboard", key_or_button) then
            return "select"
        elseif key_or_button == "escape" then
            return "cancel"
        end
    elseif source == "gamepad" then
        if input:wasPressed("menu_left", "gamepad", key_or_button) then
            return math.max(1, current_selection - 1)
        elseif input:wasPressed("menu_right", "gamepad", key_or_button) then
            return math.min(button_count, current_selection + 1)
        elseif input:wasPressed("menu_select", "gamepad", key_or_button) then
            return "select"
        elseif input:wasPressed("menu_back", "gamepad", key_or_button) then
            return "cancel"
        end
    end

    return nil
end

-- Handle touch input for menu options
-- Returns touched option index (1-based) or 0 if no option was touched
function helpers.handleTouchPress(options, layout, width, font, x, y, display_module)
    local coords = require "engine.core.coords"
    local vx, vy = coords:physicalToVirtual(x, y, display_module)

    love.graphics.setFont(font)
    for i, option in ipairs(options) do
        local option_y = layout.options_start_y + (i - 1) * layout.option_spacing
        local text_width = font:getWidth(option)
        local text_height = font:getHeight()
        local option_x = (width - text_width) / 2
        local padding = 15

        if vx >= option_x - padding and vx <= option_x + text_width + padding and
            vy >= option_y - padding and vy <= option_y + text_height + padding then
            return i
        end
    end

    return 0
end

-- Handle touch input for slot-based menus (newgame, saveslot, load)
-- Returns touched slot index (1-based) or 0 if no slot was touched
function helpers.handleSlotTouchPress(slots, layout, width, x, y, display_module)
    local coords = require "engine.core.coords"
    local vx, vy = coords:physicalToVirtual(x, y, display_module)

    for i, slot in ipairs(slots) do
        local slot_y = layout.slots_start_y + (i - 1) * layout.slot_spacing
        local slot_height = 75
        local padding = 8

        if vx >= width * 0.15 and vx <= width * 0.85 and
            vy >= slot_y - padding and vy <= slot_y + slot_height + padding then
            return i
        end
    end

    return 0
end

return helpers

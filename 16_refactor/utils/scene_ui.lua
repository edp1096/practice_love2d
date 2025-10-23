-- utils/scene_ui.lua
-- Common UI utilities for menu scenes to eliminate code duplication

local screen = require "lib.screen"
local input = require "systems.input"
local sound = require "systems.sound"

local scene_ui = {}

-- Create standard menu layout configuration
function scene_ui.createMenuLayout(vh)
    return {
        title_y = vh * 0.2,
        options_start_y = vh * 0.42,
        option_spacing = 60,
        hint_y = vh - 40
    }
end

-- Create standard fonts for menu scenes
function scene_ui.createMenuFonts()
    return {
        title = love.graphics.newFont(48),
        option = love.graphics.newFont(28),
        hint = love.graphics.newFont(16),
        label = love.graphics.newFont(24),
        info = love.graphics.newFont(16)
    }
end

-- Draw menu title
function scene_ui.drawTitle(text, font, y, width, color)
    color = color or { 1, 1, 1, 1 }
    love.graphics.setFont(font)
    love.graphics.setColor(color)
    love.graphics.printf(text, 0, y, width, "center")
end

-- Draw menu options with selection highlight
function scene_ui.drawOptions(options, selected, mouse_over, font, layout, width)
    love.graphics.setFont(font)

    for i, option in ipairs(options) do
        local y = layout.options_start_y + (i - 1) * layout.option_spacing
        local is_selected = (i == selected or i == mouse_over)

        if is_selected then
            love.graphics.setColor(1, 1, 0, 1) -- Yellow highlight
            love.graphics.printf("> " .. option, 0, y, width, "center")
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1) -- Gray normal
            love.graphics.printf(option, 0, y, width, "center")
        end
    end
end

-- Update mouse-over detection for menu options
function scene_ui.updateMouseOver(options, layout, width, font)
    local vmx, vmy = screen:GetVirtualMousePosition()
    love.graphics.setFont(font)

    for i, option in ipairs(options) do
        local y = layout.options_start_y + (i - 1) * layout.option_spacing
        local text_width = font:getWidth(option)
        local text_height = font:getHeight()
        local x = (width - text_width) / 2
        local padding = 20

        if vmx >= x - padding and vmx <= x + text_width + padding and
            vmy >= y - padding and vmy <= y + text_height + padding then
            return i
        end
    end

    return 0
end

-- Draw control hints at bottom of screen
function scene_ui.drawControlHints(font, layout, width, custom_text)
    love.graphics.setFont(font)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)

    local hint_text
    if custom_text then
        hint_text = custom_text
    elseif input:hasGamepad() then
        hint_text = "D-Pad: Navigate | " .. input:getPrompt("menu_select") .. ": Select | " ..
            input:getPrompt("menu_back") .. ": Back\n" ..
            "Keyboard: Arrow Keys / WASD | Enter: Select | Mouse: Hover & Click"
    else
        hint_text = "Arrow Keys / WASD to navigate, Enter to select | Mouse to hover and click"
    end

    love.graphics.printf(hint_text, 0, layout.hint_y - 20, width, "center")
end

-- Handle keyboard navigation (returns new selection or nil if no change)
function scene_ui.handleKeyboardNav(key, current_selection, option_count)
    if input:wasPressed("menu_up", "keyboard", key) then
        local new_sel = current_selection - 1
        if new_sel < 1 then new_sel = option_count end
        sound:playSFX("menu", "navigate")
        return new_sel
    elseif input:wasPressed("menu_down", "keyboard", key) then
        local new_sel = current_selection + 1
        if new_sel > option_count then new_sel = 1 end
        sound:playSFX("menu", "navigate")
        return new_sel
    elseif input:wasPressed("menu_select", "keyboard", key) then
        sound:playSFX("menu", "select")
        return "select"
    end

    return nil
end

-- Handle gamepad navigation
function scene_ui.handleGamepadNav(button, current_selection, option_count)
    if input:wasPressed("menu_up", "gamepad", button) then
        local new_sel = current_selection - 1
        if new_sel < 1 then new_sel = option_count end
        sound:playSFX("menu", "navigate")
        return new_sel
    elseif input:wasPressed("menu_down", "gamepad", button) then
        local new_sel = current_selection + 1
        if new_sel > option_count then new_sel = 1 end
        sound:playSFX("menu", "navigate")
        return new_sel
    elseif input:wasPressed("menu_select", "gamepad", button) then
        sound:playSFX("menu", "select")
        return "select"
    elseif input:wasPressed("menu_back", "gamepad", button) then
        sound:playSFX("menu", "back")
        return "back"
    end

    return nil
end

-- Handle mouse selection (returns selected index or nil)
function scene_ui.handleMouseSelection(button, mouse_over)
    if button == 1 and mouse_over > 0 then
        sound:playSFX("menu", "select")
        return mouse_over
    end
    return nil
end

-- Draw semi-transparent overlay (for pause/settings menus)
function scene_ui.drawOverlay(width, height, alpha)
    alpha = alpha or 0.7
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, 0, width, height)
end

-- Draw confirmation dialog (Yes/No)
function scene_ui.drawConfirmDialog(title, subtitle, button_labels, selected, mouse_over, fonts, width, height)
    button_labels = button_labels or { "No", "Yes" }

    -- Dark overlay
    love.graphics.setColor(0, 0, 0, 0.85)
    love.graphics.rectangle("fill", 0, 0, width, height)

    -- Title
    love.graphics.setFont(fonts.title or love.graphics.newFont(20))
    love.graphics.setColor(1, 0.3, 0.3, 1)
    love.graphics.printf(title, 0, height / 2 - 60, width, "center")

    -- Subtitle
    if subtitle then
        love.graphics.setFont(fonts.hint or love.graphics.newFont(14))
        love.graphics.setColor(0.9, 0.9, 0.9, 1)
        love.graphics.printf(subtitle, 0, height / 2 - 20, width, "center")
    end

    -- Buttons
    local button_y = height / 2 + 60
    local button_width = 120
    local button_height = 50
    local button_spacing = 40

    for i = 1, #button_labels do
        local button_x = width / 2 - (#button_labels * button_width + (#button_labels - 1) * button_spacing) / 2 +
            (i - 1) * (button_width + button_spacing)
        local is_selected = (i == selected or i == mouse_over)

        -- Button background
        if i == 2 then -- Yes button (dangerous action)
            love.graphics.setColor(is_selected and 0.8 or 0.5, 0.2, 0.2, is_selected and 0.9 or 0.7)
        else           -- No button (safe action)
            love.graphics.setColor(is_selected and 0.4 or 0.3, is_selected and 0.4 or 0.3,
                is_selected and 0.5 or 0.35, is_selected and 0.9 or 0.7)
        end
        love.graphics.rectangle("fill", button_x, button_y, button_width, button_height)

        -- Button border
        if i == 2 then
            love.graphics.setColor(is_selected and 1 or 0.7, 0.3, 0.3, 1)
        else
            love.graphics.setColor(is_selected and 0.7 or 0.5, is_selected and 0.7 or 0.5,
                is_selected and 0.8 or 0.5, 1)
        end
        love.graphics.rectangle("line", button_x, button_y, button_width, button_height)

        -- Button text
        love.graphics.setFont(fonts.option or love.graphics.newFont(24))
        love.graphics.setColor(is_selected and 1 or 0.9, is_selected and 1 or 0.9, is_selected and 1 or 0.9, 1)
        love.graphics.printf(button_labels[i], button_x, button_y + 12, button_width, "center")
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Update mouse-over for confirmation dialog buttons
function scene_ui.updateConfirmMouseOver(width, height, button_count)
    local vmx, vmy = screen:GetVirtualMousePosition()

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
function scene_ui.handleConfirmNav(key_or_button, source, current_selection, button_count)
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

return scene_ui

-- engine/utils/shapes.lua
-- Shape drawing utilities to reduce code duplication

local shapes = {}
local colors = require "engine.utils.colors"
local text_ui = require "engine.utils.text"

-- Draw a filled box with optional border and rounding
-- color: {r, g, b, a}
-- border_color: {r, g, b, a} (optional)
-- border_width: number (optional, default 1)
-- rounding: number (optional, corner radius)
function shapes:drawBox(x, y, w, h, color, border_color, border_width, rounding)
    rounding = rounding or 0

    -- Fill
    if color then
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, y, w, h, rounding, rounding)
    end

    -- Border
    if border_color then
        love.graphics.setColor(border_color)
        local prev_width = love.graphics.getLineWidth()
        love.graphics.setLineWidth(border_width or 1)
        love.graphics.rectangle("line", x, y, w, h, rounding, rounding)
        love.graphics.setLineWidth(prev_width)
    end

    colors:reset()
end

-- Draw a panel (box with background and border)
-- Simplified version for common UI panels
function shapes:drawPanel(x, y, w, h, bg_color, border_color, rounding)
    bg_color = bg_color or colors.DARK_CHARCOAL_80
    border_color = border_color or colors.BLUE_GRAY
    rounding = rounding or 0

    self:drawBox(x, y, w, h, bg_color, border_color, 1, rounding)
end

-- Draw a button with hover/pressed states
-- state: "normal", "hover", "pressed", "selected"
function shapes:drawButton(x, y, w, h, state, rounding)
    rounding = rounding or 3
    local bg_color, border_color, border_width

    if state == "pressed" or state == "selected" then
        bg_color = colors.for_button_selected_bg
        border_color = colors.for_item_selected
        border_width = colors.BORDER_WIDTH_MEDIUM
    elseif state == "hover" then
        bg_color = colors.for_button_hover_bg
        border_color = colors.for_gamepad_cursor
        border_width = colors.BORDER_WIDTH_MEDIUM  -- 2px for hover
    else -- normal
        bg_color = colors.for_button_normal_bg
        border_color = colors.for_button_normal_border
        border_width = colors.BORDER_WIDTH_THIN
    end

    self:drawBox(x, y, w, h, bg_color, border_color, border_width, rounding)
end

-- Draw a slot (for inventory, save slots, etc.)
-- is_selected: boolean
-- is_hovered: boolean
-- Supports both square (width only) and rectangular (width, height)
function shapes:drawSlot(x, y, width, height_or_selected, is_selected_or_hovered, is_hovered_or_rounding, rounding)
    -- Handle backward compatibility: drawSlot(x, y, size, is_selected, is_hovered, rounding)
    local w, h, selected, hovered, round

    if type(height_or_selected) == "boolean" then
        -- Old signature: (x, y, size, is_selected, is_hovered, rounding)
        w = width
        h = width
        selected = height_or_selected
        hovered = is_selected_or_hovered
        round = is_hovered_or_rounding
    else
        -- New signature: (x, y, width, height, is_selected, is_hovered, rounding)
        w = width
        h = height_or_selected or width  -- default to square if height not provided
        selected = is_selected_or_hovered
        hovered = is_hovered_or_rounding
        round = rounding
    end

    round = round or 5
    local state = selected and "selected" or (hovered and "hover" or "normal")
    self:drawButton(x, y, w, h, state, round)
end

-- Draw an overlay (dark transparent layer)
function shapes:drawOverlay(w, h, alpha)
    alpha = alpha or 0.7
    colors:apply(colors.BLACK, alpha)
    love.graphics.rectangle("fill", 0, 0, w, h)
    colors:reset()
end

-- Draw a progress bar
-- ratio: 0.0 to 1.0
-- bar_color: color when full/normal
-- bg_color: background color
-- low_color: color when ratio < 0.3 (optional)
function shapes:drawProgressBar(x, y, w, h, ratio, bar_color, bg_color, low_color)
    ratio = math.max(0, math.min(1, ratio))
    bg_color = bg_color or {0.3, 0, 0, 1}
    bar_color = bar_color or {0.8, 0.2, 0.2, 1}

    -- Background
    love.graphics.setColor(bg_color)
    love.graphics.rectangle("fill", x, y, w, h)

    -- Bar
    if ratio < 0.3 and low_color then
        love.graphics.setColor(low_color)
    else
        love.graphics.setColor(bar_color)
    end
    love.graphics.rectangle("fill", x, y, w * ratio, h)

    colors:reset()
end

-- Draw a health bar with background panel
-- Combines panel + progress bar
function shapes:drawHealthBar(x, y, w, h, hp, max_hp, show_text, font)
    -- Panel background
    colors:apply(colors.for_hud_cooldown_bg)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 22)

    -- Progress bar
    local ratio = hp / max_hp
    local bar_color = ratio < 0.3 and {0.6, 0.2, 0.2, 1} or
                      ratio < 0.6 and {0.7, 0.2, 0.2, 1} or {0.8, 0.2, 0.2, 1}
    self:drawProgressBar(x, y, w, h, ratio, bar_color, {0.3, 0, 0, 1})

    -- Text (optional)
    if show_text and font then
        text_ui:draw(string.format("HP: %d / %d", hp, max_hp), x + 5, y + 3, {1, 1, 1, 1}, font)
    end
end

-- Draw a cooldown indicator
-- Similar to progress bar but inverted (fills up when cooling down)
function shapes:drawCooldown(x, y, w, h, cd, max_cd, ready_color, cd_color)
    ready_color = ready_color or colors.PALE_GREEN
    cd_color = cd_color or colors.MEDIUM_BLUE

    -- Background
    colors:apply(colors.DARK_CHARCOAL)
    love.graphics.rectangle("fill", x, y, w, h)

    if cd > 0 then
        -- Cooldown progress (fills from left to right)
        local cd_ratio = 1 - (cd / max_cd)
        love.graphics.setColor(cd_color)
        love.graphics.rectangle("fill", x, y, w * cd_ratio, h)
    else
        -- Ready - pulse effect
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(ready_color[1], ready_color[2], ready_color[3], pulse)
        love.graphics.rectangle("fill", x, y, w, h)
    end

    colors:reset()
end

-- Draw a dialog box with title area
-- Returns y position after title for content
function shapes:drawDialog(x, y, w, h, title, title_font, title_color)
    -- Main panel
    self:drawPanel(x, y, w, h, colors.NAVY_BLUE, colors.DIM_GRAY, 10)

    -- Title area (if provided)
    if title and title_font then
        title_color = title_color or colors.WHITE

        -- Title background
        colors:apply(colors.CHARCOAL)
        love.graphics.rectangle("fill", x, y, w, 40, 10, 10)

        -- Title text
        text_ui:drawCentered(title, y + 10, w, title_color, title_font)

        return y + 50 -- Content starts below title
    end

    return y + 10 -- Content starts with padding
end

-- Draw a close button (X) with red background
function shapes:drawCloseButton(x, y, size, is_hovered)
    local rounding = 3
    local bg_color, border_color

    -- Red background for delete/close buttons
    if is_hovered then
        bg_color = colors.for_button_delete_selected
        border_color = colors.for_button_delete_border_selected
    else
        bg_color = colors.for_button_delete_normal
        border_color = colors.for_button_delete_border_normal
    end

    self:drawBox(x, y, size, size, bg_color, border_color, 1, rounding)

    -- Draw X
    colors:apply(colors.WHITE)
    local padding = size * 0.25
    love.graphics.setLineWidth(2)
    love.graphics.line(x + padding, y + padding, x + size - padding, y + size - padding)
    love.graphics.line(x + size - padding, y + padding, x + padding, y + size - padding)
    love.graphics.setLineWidth(1)
end

-- Draw a confirmation dialog with Yes/No buttons
-- Returns "yes", "no", or nil
function shapes:drawConfirmDialog(x, y, w, h, message, message_font, yes_hover, no_hover)
    -- Dialog box
    local content_y = self:drawDialog(x, y, w, h, "Confirm", message_font, {1, 1, 0.2, 1})

    -- Message
    if message and message_font then
        text_ui:drawCentered(message, content_y + 20, w, {1, 1, 1, 1}, message_font)
    end

    -- Buttons
    local button_width = 100
    local button_height = 40
    local button_spacing = 20
    local button_y = y + h - button_height - 20

    local yes_x = x + w / 2 - button_width - button_spacing / 2
    local no_x = x + w / 2 + button_spacing / 2

    -- Yes button
    local yes_state = yes_hover and "hover" or "normal"
    self:drawButton(yes_x, button_y, button_width, button_height, yes_state, 5)

    -- No button
    local no_state = no_hover and "hover" or "normal"
    self:drawButton(no_x, button_y, button_width, button_height, no_state, 5)

    -- Button text
    local text_ui = require "engine.utils.text"
    text_ui:drawCentered("Yes", button_y + 12, button_width, {1, 1, 1, 1}, message_font)
    text_ui:drawCentered("No", button_y + 12, button_width, {1, 1, 1, 1}, message_font)

    return {
        yes_x = yes_x,
        yes_y = button_y,
        no_x = no_x,
        no_y = button_y,
        button_width = button_width,
        button_height = button_height
    }
end

return shapes

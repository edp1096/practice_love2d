-- engine/ui/text.lua
-- Text rendering utilities to reduce code duplication
-- Provides common text rendering patterns with color, font, and alignment

local text = {}

-- Draw colored text with one call
-- @param str: Text to draw
-- @param x, y: Position
-- @param color: Color table {r, g, b, a} (optional, defaults to white)
-- @param font: Font to use (optional, uses current font if nil)
function text:draw(str, x, y, color, font)
    if font then love.graphics.setFont(font) end
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.print(str, x, y)
end

-- Draw colored text with printf (supports alignment and wrapping)
-- @param str: Text to draw
-- @param x, y: Position
-- @param width: Width limit for wrapping
-- @param align: Alignment ("left", "center", "right")
-- @param color: Color table {r, g, b, a} (optional, defaults to white)
-- @param font: Font to use (optional, uses current font if nil)
function text:drawf(str, x, y, width, align, color, font)
    if font then love.graphics.setFont(font) end
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.printf(str, x, y, width, align or "left")
end

-- Draw centered text (common pattern)
-- @param str: Text to draw
-- @param y: Y position
-- @param width: Width of the area to center within
-- @param color: Color table {r, g, b, a} (optional, defaults to white)
-- @param font: Font to use (optional, uses current font if nil)
function text:drawCentered(str, y, width, color, font)
    if font then love.graphics.setFont(font) end
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.printf(str, 0, y, width, "center")
end

-- Draw text with selected/unselected state (menu/option pattern)
-- @param str: Text to draw
-- @param x, y: Position
-- @param is_selected: Boolean indicating selection state
-- @param font: Font to use (optional, uses current font if nil)
-- @param selected_color: Color when selected (optional, defaults to yellow)
-- @param normal_color: Color when not selected (optional, defaults to gray)
function text:drawOption(str, x, y, is_selected, font, selected_color, normal_color)
    if font then love.graphics.setFont(font) end
    if is_selected then
        love.graphics.setColor(selected_color or {1, 1, 0, 1}) -- Yellow
    else
        love.graphics.setColor(normal_color or {0.7, 0.7, 0.7, 1}) -- Gray
    end
    love.graphics.print(str, x, y)
end

-- Draw centered text with selected/unselected state
-- @param str: Text to draw
-- @param y: Y position
-- @param width: Width of the area to center within
-- @param is_selected: Boolean indicating selection state
-- @param font: Font to use (optional, uses current font if nil)
-- @param selected_color: Color when selected (optional, defaults to yellow)
-- @param normal_color: Color when not selected (optional, defaults to gray)
function text:drawOptionCentered(str, y, width, is_selected, font, selected_color, normal_color)
    if font then love.graphics.setFont(font) end
    if is_selected then
        love.graphics.setColor(selected_color or {1, 1, 0, 1}) -- Yellow
    else
        love.graphics.setColor(normal_color or {0.7, 0.7, 0.7, 1}) -- Gray
    end
    love.graphics.printf(str, 0, y, width, "center")
end

-- Draw text with printf with selected/unselected state
-- @param str: Text to draw
-- @param x, y: Position
-- @param width: Width limit
-- @param align: Alignment ("left", "center", "right")
-- @param is_selected: Boolean indicating selection state
-- @param font: Font to use (optional, uses current font if nil)
-- @param selected_color: Color when selected (optional, defaults to yellow)
-- @param normal_color: Color when not selected (optional, defaults to gray)
function text:drawOptionAligned(str, x, y, width, align, is_selected, font, selected_color, normal_color)
    if font then love.graphics.setFont(font) end
    if is_selected then
        love.graphics.setColor(selected_color or {1, 1, 0, 1}) -- Yellow
    else
        love.graphics.setColor(normal_color or {0.7, 0.7, 0.7, 1}) -- Gray
    end
    love.graphics.printf(str, x, y, width, align or "left")
end

-- Draw text with shadow (improves readability over complex backgrounds)
-- @param str: Text to draw
-- @param x, y: Position
-- @param color: Text color (optional, defaults to white)
-- @param shadow_offset: Shadow offset in pixels (optional, defaults to 2)
-- @param shadow_alpha: Shadow transparency (optional, defaults to 0.5)
-- @param font: Font to use (optional, uses current font if nil)
function text:drawWithShadow(str, x, y, color, shadow_offset, shadow_alpha, font)
    shadow_offset = shadow_offset or 2
    shadow_alpha = shadow_alpha or 0.5
    if font then love.graphics.setFont(font) end

    -- Shadow
    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.print(str, x + shadow_offset, y + shadow_offset)

    -- Text
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.print(str, x, y)
end

-- Draw centered text with shadow
-- @param str: Text to draw
-- @param y: Y position
-- @param width: Width of the area to center within
-- @param color: Text color (optional, defaults to white)
-- @param shadow_offset: Shadow offset in pixels (optional, defaults to 2)
-- @param shadow_alpha: Shadow transparency (optional, defaults to 0.5)
-- @param font: Font to use (optional, uses current font if nil)
function text:drawCenteredWithShadow(str, y, width, color, shadow_offset, shadow_alpha, font)
    shadow_offset = shadow_offset or 2
    shadow_alpha = shadow_alpha or 0.5
    if font then love.graphics.setFont(font) end

    -- Shadow
    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.printf(str, 0, y + shadow_offset, width, "center")

    -- Text
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.printf(str, 0, y, width, "center")
end

-- Draw text with outline (alternative to shadow for readability)
-- @param str: Text to draw
-- @param x, y: Position
-- @param color: Text color (optional, defaults to white)
-- @param outline_color: Outline color (optional, defaults to black)
-- @param outline_width: Outline thickness (optional, defaults to 1)
-- @param font: Font to use (optional, uses current font if nil)
function text:drawWithOutline(str, x, y, color, outline_color, outline_width, font)
    outline_color = outline_color or {0, 0, 0, 1}
    outline_width = outline_width or 1
    if font then love.graphics.setFont(font) end

    -- Draw outline (8-directional)
    love.graphics.setColor(outline_color)
    for ox = -outline_width, outline_width do
        for oy = -outline_width, outline_width do
            if ox ~= 0 or oy ~= 0 then
                love.graphics.print(str, x + ox, y + oy)
            end
        end
    end

    -- Draw main text
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.print(str, x, y)
end

return text

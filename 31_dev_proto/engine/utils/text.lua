-- engine/utils/text.lua
-- Text rendering utilities to reduce code duplication

local text = {}

-- Basic text drawing
function text:draw(str, x, y, color, font)
    if font then love.graphics.setFont(font) end
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.print(str, x, y)
end

-- Text with alignment and wrapping
function text:drawf(str, x, y, width, align, color, font)
    if font then love.graphics.setFont(font) end
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.printf(str, x, y, width, align or "left")
end

-- Centered text
function text:drawCentered(str, y, width, color, font)
    if font then love.graphics.setFont(font) end
    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.printf(str, 0, y, width, "center")
end

-- Menu option (selected = yellow, normal = gray)
function text:drawOption(str, x, y, is_selected, font, selected_color, normal_color)
    if font then love.graphics.setFont(font) end
    if is_selected then
        love.graphics.setColor(selected_color or {1, 1, 0, 1})
    else
        love.graphics.setColor(normal_color or {0.7, 0.7, 0.7, 1})
    end
    love.graphics.print(str, x, y)
end

-- Centered menu option
function text:drawOptionCentered(str, y, width, is_selected, font, selected_color, normal_color)
    if font then love.graphics.setFont(font) end
    if is_selected then
        love.graphics.setColor(selected_color or {1, 1, 0, 1})
    else
        love.graphics.setColor(normal_color or {0.7, 0.7, 0.7, 1})
    end
    love.graphics.printf(str, 0, y, width, "center")
end

-- Aligned menu option
function text:drawOptionAligned(str, x, y, width, align, is_selected, font, selected_color, normal_color)
    if font then love.graphics.setFont(font) end
    if is_selected then
        love.graphics.setColor(selected_color or {1, 1, 0, 1})
    else
        love.graphics.setColor(normal_color or {0.7, 0.7, 0.7, 1})
    end
    love.graphics.printf(str, x, y, width, align or "left")
end

-- Text with drop shadow
function text:drawWithShadow(str, x, y, color, shadow_offset, shadow_alpha, font)
    shadow_offset = shadow_offset or 2
    shadow_alpha = shadow_alpha or 0.5
    if font then love.graphics.setFont(font) end

    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.print(str, x + shadow_offset, y + shadow_offset)

    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.print(str, x, y)
end

-- Centered text with shadow
function text:drawCenteredWithShadow(str, y, width, color, shadow_offset, shadow_alpha, font)
    shadow_offset = shadow_offset or 2
    shadow_alpha = shadow_alpha or 0.5
    if font then love.graphics.setFont(font) end

    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.printf(str, 0, y + shadow_offset, width, "center")

    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.printf(str, 0, y, width, "center")
end

-- Text with outline (8-directional)
function text:drawWithOutline(str, x, y, color, outline_color, outline_width, font)
    outline_color = outline_color or {0, 0, 0, 1}
    outline_width = outline_width or 1
    if font then love.graphics.setFont(font) end

    love.graphics.setColor(outline_color)
    for ox = -outline_width, outline_width do
        for oy = -outline_width, outline_width do
            if ox ~= 0 or oy ~= 0 then
                love.graphics.print(str, x + ox, y + oy)
            end
        end
    end

    love.graphics.setColor(color or {1, 1, 1, 1})
    love.graphics.print(str, x, y)
end

return text

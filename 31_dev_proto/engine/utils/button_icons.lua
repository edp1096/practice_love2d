-- engine/utils/button_icons.lua
-- Draw controller button icons (shapes for PlayStation, text for Xbox)

local button_icons = {}

-- PlayStation button colors (DualSense style)
local PS_COLORS = {
    cross = {0.28, 0.47, 0.81},      -- Blue
    circle = {1, 0.25, 0.27},        -- Red
    square = {0.84, 0.35, 0.61},     -- Pink
    triangle = {0, 0.65, 0.31}       -- Green
}

-- Draw PlayStation button icon
-- x, y: center position
-- button: "cross", "circle", "square", "triangle"
-- size: icon size (default 16)
function button_icons:drawPlayStation(x, y, button, size)
    size = size or 16
    local radius = size / 2

    love.graphics.push()
    love.graphics.translate(x, y)

    if button == "cross" then
        -- Draw X (two diagonal lines)
        love.graphics.setColor(PS_COLORS.cross)
        love.graphics.setLineWidth(2)
        local offset = radius * 0.6
        love.graphics.line(-offset, -offset, offset, offset)
        love.graphics.line(offset, -offset, -offset, offset)

    elseif button == "circle" then
        -- Draw circle
        love.graphics.setColor(PS_COLORS.circle)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", 0, 0, radius * 0.7)

    elseif button == "square" then
        -- Draw square
        love.graphics.setColor(PS_COLORS.square)
        love.graphics.setLineWidth(2)
        local half = radius * 0.7
        love.graphics.rectangle("line", -half, -half, half * 2, half * 2)

    elseif button == "triangle" then
        -- Draw triangle
        love.graphics.setColor(PS_COLORS.triangle)
        love.graphics.setLineWidth(2)
        local h = radius * 0.8
        love.graphics.polygon("line", 0, -h, h, h * 0.7, -h, h * 0.7)
    end

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Draw Xbox button (just text)
function button_icons:drawXbox(x, y, button, font)
    font = font or love.graphics.getFont()
    local text = button:upper()
    local tw = font:getWidth(text)
    local th = font:getHeight()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(text, x - tw / 2, y - th / 2)
end

-- Draw hamburger menu icon (3 horizontal lines)
-- x, y: center position
-- size: icon size (default 16)
-- color: optional color (default white)
function button_icons:drawHamburger(x, y, size, color)
    size = size or 16
    color = color or {1, 1, 1}

    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.setColor(color)
    love.graphics.setLineWidth(2)

    local width = size * 0.8
    local spacing = size * 0.3

    -- Top line
    love.graphics.line(-width / 2, -spacing, width / 2, -spacing)
    -- Middle line
    love.graphics.line(-width / 2, 0, width / 2, 0)
    -- Bottom line
    love.graphics.line(-width / 2, spacing, width / 2, spacing)

    love.graphics.pop()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Generic draw function (auto-detects type)
function button_icons:draw(x, y, button, gamepad_type, size, font)
    if gamepad_type == "playstation" then
        self:drawPlayStation(x, y, button, size)
    else
        self:drawXbox(x, y, button, font)
    end
end

return button_icons

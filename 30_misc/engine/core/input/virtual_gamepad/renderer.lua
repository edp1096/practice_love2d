-- engine/core/input/virtual_gamepad/renderer.lua
-- Rendering functions for virtual gamepad

local text_ui = require "engine.utils.text"
local button_icons = require "engine.utils.button_icons"
local colors = require "engine.utils.colors"

local renderer = {}

-- Draw virtual gamepad overlay
function renderer.draw(vgp)
    if not vgp.enabled or not vgp.visible then return end

    -- Cache scale for drawing
    vgp.draw_scale = vgp.display:GetScale()

    -- No push/pop/origin needed - we draw in physical space after display:Detach()
    -- Draw D-pad
    renderer.drawDPad(vgp)

    -- Draw aim stick
    renderer.drawAimStick(vgp)

    -- Draw action buttons
    renderer.drawActionButtons(vgp)

    -- Draw menu button
    renderer.drawMenuButton(vgp)
end

function renderer.drawDPad(vgp)
    -- Convert virtual coordinates to physical coordinates
    local px, py = vgp:toPhysical(vgp.dpad.x, vgp.dpad.y)
    local scale = vgp.draw_scale or 1
    local r = vgp.dpad.radius * scale

    -- Outer circle
    colors:apply(colors.for_gamepad_bg, vgp.alpha)
    love.graphics.circle("fill", px, py, r)
    colors:apply(colors.for_gamepad_border, vgp.alpha * 1.5)
    love.graphics.setLineWidth(3 * scale)
    love.graphics.circle("line", px, py, r)

    -- Directional indicators
    colors:apply(colors.for_gamepad_button, vgp.alpha)

    -- Up arrow
    if vgp.dpad_direction.up then
        colors:apply(colors.for_gamepad_stick, vgp.alpha * 2)
    end
    love.graphics.polygon("fill",
        px, py - r + 20 * scale,
        px - 18 * scale, py - r + 45 * scale,
        px + 18 * scale, py - r + 45 * scale
    )

    -- Down arrow
    colors:apply(colors.for_gamepad_button, vgp.alpha)
    if vgp.dpad_direction.down then
        colors:apply(colors.for_gamepad_stick, vgp.alpha * 2)
    end
    love.graphics.polygon("fill",
        px, py + r - 20 * scale,
        px - 18 * scale, py + r - 45 * scale,
        px + 18 * scale, py + r - 45 * scale
    )

    -- Left arrow
    colors:apply(colors.for_gamepad_button, vgp.alpha)
    if vgp.dpad_direction.left then
        colors:apply(colors.for_gamepad_stick, vgp.alpha * 2)
    end
    love.graphics.polygon("fill",
        px - r + 20 * scale, py,
        px - r + 45 * scale, py - 18 * scale,
        px - r + 45 * scale, py + 18 * scale
    )

    -- Right arrow
    colors:apply(colors.for_gamepad_button, vgp.alpha)
    if vgp.dpad_direction.right then
        colors:apply(colors.for_gamepad_stick, vgp.alpha * 2)
    end
    love.graphics.polygon("fill",
        px + r - 20 * scale, py,
        px + r - 45 * scale, py - 18 * scale,
        px + r - 45 * scale, py + 18 * scale
    )

    -- Center knob
    local knob_x = px + (vgp.stick_x * (r - 30 * scale))
    local knob_y = py + (vgp.stick_y * (r - 30 * scale))

    colors:apply(colors.CHARCOAL, vgp.alpha * 1.2)
    love.graphics.circle("fill", knob_x, knob_y, vgp.dpad.center_radius * scale)
    colors:apply(colors.DARK_GRAY, vgp.alpha * 1.5)
    love.graphics.setLineWidth(2 * scale)
    love.graphics.circle("line", knob_x, knob_y, vgp.dpad.center_radius * scale)

    love.graphics.setLineWidth(1)
    colors:reset()
end

-- Draw aim stick
function renderer.drawAimStick(vgp)
    local stick = vgp.aim_stick
    local px, py = vgp:toPhysical(stick.x, stick.y)
    local scale = vgp.draw_scale or 1
    local r = stick.radius * scale

    -- Outer circle (base)
    colors:apply(colors.for_gamepad_bg, vgp.alpha * 0.7)
    love.graphics.circle("fill", px, py, r)
    colors:apply(colors.for_gamepad_border, vgp.alpha * 1.2)
    love.graphics.setLineWidth(3 * scale)
    love.graphics.circle("line", px, py, r)

    -- Center crosshair indicator
    colors:apply(colors.DARK_GRAY, vgp.alpha * 0.8)
    love.graphics.setLineWidth(2 * scale)
    local cross_size = 12 * scale
    love.graphics.line(px - cross_size, py, px + cross_size, py)
    love.graphics.line(px, py - cross_size, px, py + cross_size)

    -- Inner stick position
    local stick_px = px + stick.offset_x * scale
    local stick_py = py + stick.offset_y * scale

    -- Direction line (if active)
    if stick.active and stick.magnitude > stick.deadzone then
        colors:apply(colors.for_gamepad_active, vgp.alpha * 1.2)
        love.graphics.setLineWidth(3 * scale)
        love.graphics.line(px, py, stick_px, stick_py)
    end

    -- Stick knob
    if stick.active then
        -- Active - yellow/gold
        colors:apply(colors.for_gamepad_active, vgp.alpha * 1.5)
    else
        -- Inactive - gray
        colors:apply(colors.CHARCOAL, vgp.alpha * 1.2)
    end
    love.graphics.circle("fill", stick_px, stick_py, stick.center_radius * scale)

    -- Stick outline
    if stick.active then
        colors:apply(colors.PASTEL_YELLOW, vgp.alpha * 1.8)
    else
        colors:apply(colors.DARK_GRAY, vgp.alpha * 1.5)
    end
    love.graphics.setLineWidth(2 * scale)
    love.graphics.circle("line", stick_px, stick_py, stick.center_radius * scale)

    -- Label
    text_ui:draw("AIM", px - 15 * scale, py + r + 10 * scale, colors:withAlpha(colors.WHITE, vgp.alpha * 1.5))

    love.graphics.setLineWidth(1)
    colors:reset()
end

function renderer.drawActionButtons(vgp)
    local scale = vgp.draw_scale or 1

    for name, button in pairs(vgp.buttons) do
        local px, py = vgp:toPhysical(button.x, button.y)
        local radius = (vgp.button_size / 2) * scale

        -- Button circle
        if button.pressed then
            colors:apply(colors.MEDIUM_BLUE, vgp.alpha * 1.5)
        else
            colors:apply(colors.for_gamepad_bg, vgp.alpha)
        end
        love.graphics.circle("fill", px, py, radius)

        -- Button outline
        if button.pressed then
            colors:apply(colors.SKY_BLUE, vgp.alpha * 2)
        else
            colors:apply(colors.for_gamepad_border, vgp.alpha * 1.5)
        end
        love.graphics.setLineWidth(3 * scale)
        love.graphics.circle("line", px, py, radius)

        -- Button label
        local font = love.graphics.getFont()
        local text_w = font:getWidth(button.label)
        local text_h = font:getHeight()
        text_ui:draw(button.label, px - text_w / 2, py - text_h / 2, colors:withAlpha(colors.WHITE, vgp.alpha * 2))
    end

    love.graphics.setLineWidth(1)
    colors:reset()
end

function renderer.drawMenuButton(vgp)
    local button = vgp.menu_button
    local px, py = vgp:toPhysical(button.x, button.y)
    local scale = vgp.draw_scale or 1
    local radius = button.radius * scale

    -- Button circle
    if button.pressed then
        colors:apply(colors.MEDIUM_BLUE, vgp.alpha * 1.5)
    else
        colors:apply(colors.for_gamepad_bg, vgp.alpha)
    end
    love.graphics.circle("fill", px, py, radius)

    -- Button outline
    if button.pressed then
        colors:apply(colors.SKY_BLUE, vgp.alpha * 2)
    else
        colors:apply(colors.for_gamepad_border, vgp.alpha * 1.5)
    end
    love.graphics.setLineWidth(3 * scale)
    love.graphics.circle("line", px, py, radius)

    -- Hamburger menu icon (3 horizontal lines)
    local icon_size = radius * 1.2  -- Icon size relative to button radius
    local icon_color = colors:withAlpha(colors.WHITE, vgp.alpha * 2)
    button_icons:drawHamburger(px, py, icon_size, icon_color)

    love.graphics.setLineWidth(1)
    colors:reset()
end

return renderer

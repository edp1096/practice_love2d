-- engine/entities/vehicle/render.lua
-- Vehicle rendering: sprite-based with colored box fallback

local constants = require "engine.core.constants"

local render = {}

-- Local references to constants for performance
local SHADOW = constants.SHADOW

function render.draw(vehicle)
    local x, y = vehicle.x, vehicle.y
    local direction = vehicle.direction or "down"

    -- Apply vibration offset when boarded and moving
    if vehicle.vibration_offset and vehicle.vibration_offset ~= 0 then
        y = y + vehicle.vibration_offset
    end

    -- If sprite available, use sprite rendering
    if vehicle.sprite_sheet and vehicle.sprite_quads and vehicle.sprite_quads[direction] then
        render.drawSprite(vehicle, x, y, direction)
    else
        render.drawColorBox(vehicle, x, y, direction)
    end
end

function render.drawSprite(vehicle, x, y, direction)
    local quad = vehicle.sprite_quads[direction]
    local scale = vehicle.sprite_scale or 2
    local fw = vehicle.sprite_config.frame_width
    local fh = vehicle.sprite_config.frame_height

    -- Calculate scaled dimensions for shadow
    local scaled_w = fw * scale
    local scaled_h = fh * scale

    -- Shadow (at bottom of vehicle)
    local shadow_y = y + scaled_h / 2 - 8
    love.graphics.setColor(0, 0, 0, SHADOW.ALPHA)
    love.graphics.ellipse("fill", x, shadow_y, scaled_w * SHADOW.VEHICLE_SPRITE_WIDTH_RATIO, scaled_h * SHADOW.VEHICLE_SPRITE_HEIGHT_RATIO)

    -- Draw sprite centered at (x, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        vehicle.sprite_sheet,
        quad,
        x, y,
        0,
        scale, scale,
        fw / 2, fh / 2  -- Origin at center
    )
end

function render.drawColorBox(vehicle, x, y, direction)
    local base_w, base_h = vehicle.width, vehicle.height

    -- Adjust dimensions based on direction
    -- Left/Right: side view (wide, short) - 64x40
    -- Up/Down: front/back view (narrow, same height) - 40x40
    local w, h
    if direction == "left" or direction == "right" then
        w, h = base_w, base_h  -- 64x40 (side view)
    else
        w, h = base_h, base_h  -- 40x40 (front/back view, width shrinks)
    end

    -- Shadow (at bottom of vehicle)
    local shadow_y = y + h / 2 - 4
    love.graphics.setColor(0, 0, 0, SHADOW.ALPHA)
    love.graphics.ellipse("fill", x, shadow_y, w * SHADOW.VEHICLE_COLORBOX_WIDTH_RATIO, h * SHADOW.VEHICLE_COLORBOX_HEIGHT_RATIO)

    -- Vehicle body (colored box with rounded corners effect)
    local r, g, b, a = unpack(vehicle.color)
    love.graphics.setColor(r, g, b, a)
    love.graphics.rectangle("fill", x - w/2, y - h/2, w, h, 4, 4)

    -- Darker border
    love.graphics.setColor(r * 0.6, g * 0.6, b * 0.6, a)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x - w/2, y - h/2, w, h, 4, 4)
    love.graphics.setLineWidth(1)

    -- Head indicator position based on direction
    -- up: player moving up (away from camera) -> head at top (far side)
    -- down: player moving down (toward camera) -> head at bottom (near side)
    love.graphics.setColor(r * 0.8, g * 0.8, b * 0.8, a)
    local head_size = math.min(w, h) * 0.3
    local head_x, head_y = x, y

    if direction == "up" then
        head_y = y - h/2 + head_size/2  -- Head at top (facing away)
    elseif direction == "down" then
        head_y = y - h/2 + head_size/2  -- Head at top (vehicle faces same as player)
    elseif direction == "left" then
        head_x = x - w/2 + head_size/2
    elseif direction == "right" then
        head_x = x + w/2 - head_size/2
    end

    love.graphics.circle("fill", head_x, head_y, head_size/2)

    love.graphics.setColor(1, 1, 1, 1)
end

return render

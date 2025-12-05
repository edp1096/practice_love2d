-- engine/entities/vehicle/render.lua
-- Vehicle rendering: colored box prototype (sprites later)

local render = {}

function render.draw(vehicle)
    local x, y = vehicle.x, vehicle.y
    local base_w, base_h = vehicle.width, vehicle.height
    local direction = vehicle.direction or "down"

    -- Apply vibration offset when boarded and moving
    if vehicle.vibration_offset and vehicle.vibration_offset ~= 0 then
        y = y + vehicle.vibration_offset
    end

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
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", x, shadow_y, w * 0.4, h * 0.2)

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

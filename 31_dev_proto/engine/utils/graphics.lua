-- engine/utils/graphics.lua
-- Graphics state management helpers

local graphics = {}

-- Reset graphics state to default (white color, line width 1)
function graphics:resetState()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Execute a function with specific graphics state, then restore
-- Usage: graphics:withState({1, 0, 0}, 2, function() ... end)
function graphics:withState(color, lineWidth, func)
    -- Save current state
    local r, g, b, a = love.graphics.getColor()
    local prevLineWidth = love.graphics.getLineWidth()

    -- Apply new state
    if color then
        love.graphics.setColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    if lineWidth then
        love.graphics.setLineWidth(lineWidth)
    end

    -- Execute function
    func()

    -- Restore previous state
    love.graphics.setColor(r, g, b, a)
    love.graphics.setLineWidth(prevLineWidth)
end

-- Set color and execute function, then reset to white
function graphics:withColor(color, func)
    love.graphics.setColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    func()
    love.graphics.setColor(1, 1, 1, 1)
end

-- Set line width and execute function, then reset to 1
function graphics:withLineWidth(width, func)
    local prev = love.graphics.getLineWidth()
    love.graphics.setLineWidth(width)
    func()
    love.graphics.setLineWidth(prev)
end

return graphics

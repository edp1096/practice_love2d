-- engine/systems/collision/shapes/rectangle.lua
-- Rectangle shape handler for wall colliders

local rectangle = {}

function rectangle.create(world, object)
    local wall = world:newRectangleCollider(object.x, object.y, object.width, object.height)
    return true, wall
end

return rectangle

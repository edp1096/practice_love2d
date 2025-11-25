-- engine/systems/collision/shapes/ellipse.lua
-- Ellipse shape handler for wall colliders

local ellipse = {}

function ellipse.create(world, object)
    local radius = math.min(object.width, object.height) / 2
    local wall = world:newCircleCollider(
        object.x + object.width / 2,
        object.y + object.height / 2,
        radius
    )
    return true, wall
end

return ellipse

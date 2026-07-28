-- engine/systems/collision/prop.lua
-- Collision setup for Prop entities

local prop_collision = {}

-- Create collider for a Prop entity
-- Topdown: uses PropFoot for actual collision (like Player/Enemy)
-- Platformer: uses single Prop collider
function prop_collision.create(prop, physicsWorld, game_mode)
    local x = prop.x
    local y = prop.y
    local w = prop.collider_width
    local h = prop.collider_height

    if game_mode == "topdown" then
        -- Topdown mode: create foot collider at bottom portion
        -- Foot collider is the bottom 25% of the prop
        local foot_height = h * 0.25
        -- foot_y is the TOP of the foot collider (bottom 25% of prop)
        local foot_y = y + (h / 2) - foot_height

        local foot_collider = physicsWorld:newRectangleCollider(
            x - w / 2,
            foot_y,
            w,
            foot_height
        )

        if prop.movable then
            foot_collider:setType("dynamic")
            foot_collider:setMass(5)
            foot_collider:setLinearDamping(10)
            foot_collider:setAngularDamping(10)
            foot_collider:setFixedRotation(true)
        else
            foot_collider:setType("static")
        end

        foot_collider:setCollisionClass("PropFoot")
        foot_collider:setObject(prop)

        prop.collider = foot_collider
        prop.foot_collider = foot_collider  -- Alias for consistency
    else
        -- Platformer mode: single collider
        local collider = physicsWorld:newRectangleCollider(x - w/2, y - h/2, w, h)

        if prop.movable then
            collider:setType("dynamic")
            collider:setMass(5)
            collider:setLinearDamping(10)
            collider:setAngularDamping(10)
            collider:setFixedRotation(true)
        else
            collider:setType("static")
        end

        collider:setCollisionClass("Prop")
        collider:setObject(prop)

        prop.collider = collider
    end
end

return prop_collision

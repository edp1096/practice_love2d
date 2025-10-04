-- systems/world.lua
-- Manages map loading, rendering, and collision system integration

local sti = require "vendor.sti"
local windfield = require "vendor.windfield"

local world = {}
world.__index = world

function world:new(map_path)
    local instance = setmetatable({}, world)

    instance.map = sti(map_path)                           -- Load map using STI
    instance.physicsWorld = windfield.newWorld(0, 0, true) -- Initialize Windfield physics world (no gravity)

    -- Setup collision classes
    instance.physicsWorld:addCollisionClass("Player")
    instance.physicsWorld:addCollisionClass("Wall")
    instance.physicsWorld:addCollisionClass("Enemy")
    instance.physicsWorld:addCollisionClass("Item")

    -- Create wall colliders from Tiled map
    instance.walls = {}
    if instance.map.layers["Walls"] then
        for i, obj in ipairs(instance.map.layers["Walls"].objects) do
            local wall = instance.physicsWorld:newRectangleCollider(
                obj.x, obj.y, obj.width, obj.height
            )
            wall:setType("static")
            wall:setCollisionClass("Wall")
            table.insert(instance.walls, wall)
        end
    end

    return instance
end

function world:addEntity(entity)
    -- Create collider for entity if it doesn't have one
    if not entity.collider then
        entity.collider = self.physicsWorld:newBSGRectangleCollider(
            entity.x, entity.y,
            entity.width, entity.height,
            10 -- corner radius
        )
        entity.collider:setFixedRotation(true)
        entity.collider:setCollisionClass("Player")
    end
end

function world:moveEntity(entity, vx, vy, dt)
    -- Apply velocity to entity's collider
    if entity.collider then entity.collider:setLinearVelocity(vx, vy) end
end

function world:update(dt)
    self.physicsWorld:update(dt) -- Update physics simulation
    self.map:update(dt)          -- Update map animations if any
end

function world:drawLayer(layer_name)
    local layer = self.map.layers[layer_name]
    if layer then self.map:drawLayer(layer) end
end

function world:drawDebug()
    self.physicsWorld:draw() -- Draw collision shapes for debugging
end

function world:destroy()
    -- Cleanup resources
    if self.physicsWorld then self.physicsWorld:destroy() end
end

return world

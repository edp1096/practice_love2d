-- systems/world.lua
-- Manages map loading, rendering, and collision system integration

local sti = require "vendor.sti"
local windfield = require "vendor.windfield"

local world = {}
world.__index = world

function world:new(map_path)
    local instance = setmetatable({}, world)

    -- Check if map file exists
    local map_info = love.filesystem.getInfo(map_path)
    if not map_info then
        error("Map file not found: " .. map_path)
    end

    instance.map = sti(map_path)                           -- Load map using STI
    instance.physicsWorld = windfield.newWorld(0, 0, true) -- Initialize Windfield physics world (no gravity)

    -- Setup collision classes
    instance.physicsWorld:addCollisionClass("Player")
    instance.physicsWorld:addCollisionClass("Wall")
    instance.physicsWorld:addCollisionClass("Portals")
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

    -- Load portal/transition areas
    instance:loadTransitions() -- Changed from self to instance

    instance.enemies = {}
    instance:loadEnemies()

    return instance
end

function world:update(dt)
    self.physicsWorld:update(dt) -- Update physics simulation
    self.map:update(dt)          -- Update map animations if any
end

function world:destroy()
    -- Cleanup resources
    if self.physicsWorld then self.physicsWorld:destroy() end
end

function world:loadTransitions()
    self.transitions = {}

    if self.map.layers["Portals"] then
        for _, obj in ipairs(self.map.layers["Portals"].objects) do
            if obj.properties.type == "portal" then
                -- Calculate bounding box for polygon or use rectangle dimensions
                local min_x, min_y, max_x, max_y = obj.x, obj.y, obj.x, obj.y

                if obj.shape == "polygon" and obj.polygon then
                    -- Find bounding box of polygon
                    for _, point in ipairs(obj.polygon) do
                        min_x = math.min(min_x, obj.x + point.x)
                        min_y = math.min(min_y, obj.y + point.y)
                        max_x = math.max(max_x, obj.x + point.x)
                        max_y = math.max(max_y, obj.y + point.y)
                    end
                else
                    -- Rectangle
                    max_x = obj.x + obj.width
                    max_y = obj.y + obj.height
                end

                table.insert(self.transitions, {
                    x = min_x,
                    y = min_y,
                    width = max_x - min_x,
                    height = max_y - min_y,
                    target_map = obj.properties.target_map,
                    spawn_x = obj.properties.spawn_x or 100,
                    spawn_y = obj.properties.spawn_y or 100
                })
            end
        end
    end
end

function world:checkTransition(player_x, player_y, player_w, player_h)
    for _, transition in ipairs(self.transitions) do
        -- Simple AABB collision check
        if player_x < transition.x + transition.width and
            player_x + player_w > transition.x and
            player_y < transition.y + transition.height and
            player_y + player_h > transition.y then
            return transition
        end
    end
    return nil
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

function world:loadEnemies()
    if self.map.layers["Enemies"] then
        local enemy_module = require "entities.enemy"

        for _, obj in ipairs(self.map.layers["Enemies"].objects) do
            local new_enemy = enemy_module:new(obj.x, obj.y, obj.properties.type or "green_slime")

            -- Give enemy reference to world for line of sight checks
            new_enemy.world = self

            -- Set patrol points from Tiled properties
            if obj.properties.patrol_points then
                local points = {}
                for point_str in string.gmatch(obj.properties.patrol_points, "([^;]+)") do
                    local x, y = point_str:match("([^,]+),([^,]+)")
                    -- Add enemy spawn position to make it relative
                    table.insert(points, {
                        x = obj.x + tonumber(x),
                        y = obj.y + tonumber(y)
                    })
                end
                new_enemy:setPatrolPoints(points)
            else
                -- Default patrol: small square around spawn position
                new_enemy:setPatrolPoints({
                    { x = obj.x - 50, y = obj.y - 50 },
                    { x = obj.x + 50, y = obj.y - 50 },
                    { x = obj.x + 50, y = obj.y + 50 },
                    { x = obj.x - 50, y = obj.y + 50 }
                })
            end

            -- Create collider
            local bounds = new_enemy:getColliderBounds()
            new_enemy.collider = self.physicsWorld:newBSGRectangleCollider(
                bounds.x, bounds.y,
                bounds.width, bounds.height,
                8
            )
            new_enemy.collider:setFixedRotation(true)
            new_enemy.collider:setCollisionClass("Enemy")
            new_enemy.collider:setObject(new_enemy)

            table.insert(self.enemies, new_enemy)
        end
    end
end

function world:checkLineOfSight(x1, y1, x2, y2)
    -- Raycast from enemy to player
    local items = self.physicsWorld:queryLine(x1, y1, x2, y2)

    -- Check if any wall collider is blocking
    for _, item in ipairs(items) do
        if item.collision_class == "Wall" then
            return false -- Blocked by wall
        end
    end

    return true -- Clear line of sight
end

function world:addEnemy(enemy)
    -- Create collider for enemy
    local bounds = enemy:getColliderBounds()
    enemy.collider = self.physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    enemy.collider:setFixedRotation(true)
    enemy.collider:setCollisionClass("Enemy")
    enemy.collider:setObject(enemy) -- Store reference

    table.insert(self.enemies, enemy)
end

function world:updateEnemies(dt, player_x, player_y)
    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]

        if enemy.state == "dead" then
            -- Remove dead enemies after delay
            enemy.death_timer = (enemy.death_timer or 0) + dt
            if enemy.death_timer > 2 then
                if enemy.collider then
                    enemy.collider:destroy()
                end
                table.remove(self.enemies, i)
            end
        else
            local vx, vy = enemy:update(dt, player_x, player_y)

            if enemy.collider then
                enemy.collider:setLinearVelocity(vx, vy)
                -- Sync position back from collider, considering offset
                enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                enemy.y = enemy.collider:getY() - enemy.collider_offset_y
            end
        end
    end
end

function world:drawEnemies()
    for _, enemy in ipairs(self.enemies) do
        enemy:draw()
    end
end

function world:drawLayer(layer_name)
    local layer = self.map.layers[layer_name]
    if layer then self.map:drawLayer(layer) end
end

function world:drawDebug()
    self.physicsWorld:draw() -- Draw collision shapes for debugging

    -- Draw portal/transition areas in debug mode
    if self.transitions then
        love.graphics.setColor(0, 1, 0, 0.3)
        for _, transition in ipairs(self.transitions) do
            love.graphics.rectangle("fill", transition.x, transition.y, transition.width, transition.height)
        end

        love.graphics.setColor(0, 1, 0, 1)
        for _, transition in ipairs(self.transitions) do
            love.graphics.rectangle("line", transition.x, transition.y, transition.width, transition.height)
        end
    end
end

return world

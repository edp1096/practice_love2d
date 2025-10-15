-- systems/world.lua
-- Manages map loading, rendering, and collision system integration with effects

local sti = require "vendor.sti"
local windfield = require "vendor.windfield"
local effects = require "systems.effects"

local world = {}
world.__index = world

function world:new(map_path)
    local instance = setmetatable({}, world)

    local map_info = love.filesystem.getInfo(map_path)
    if not map_info then
        error("Map file not found: " .. map_path)
    end

    instance.map = sti(map_path)
    instance.physicsWorld = windfield.newWorld(0, 0, true)

    -- Setup collision classes
    instance.physicsWorld:addCollisionClass("Player")
    instance.physicsWorld:addCollisionClass("PlayerDodging")
    instance.physicsWorld:addCollisionClass("Wall")
    instance.physicsWorld:addCollisionClass("Portals")
    instance.physicsWorld:addCollisionClass("Enemy")
    instance.physicsWorld:addCollisionClass("Item")

    -- Set ignore rules directly in collision_classes table
    instance.physicsWorld.collision_classes.PlayerDodging.ignores = { "Enemy" }

    -- Regenerate masks
    instance.physicsWorld:collisionClassesSet()

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

    instance:loadTransitions()

    instance.enemies = {}
    instance:loadEnemies()

    instance.npcs = {}
    instance:loadNPCs()

    return instance
end

function world:update(dt)
    self.physicsWorld:update(dt)
    self.map:update(dt)
    effects:update(dt)
end

function world:destroy()
    if self.physicsWorld then self.physicsWorld:destroy() end
end

function world:loadTransitions()
    self.transitions = {}

    if self.map.layers["Portals"] then
        for _, obj in ipairs(self.map.layers["Portals"].objects) do
            if obj.properties.type == "portal" then
                local min_x, min_y, max_x, max_y = obj.x, obj.y, obj.x, obj.y

                if obj.shape == "polygon" and obj.polygon then
                    for _, point in ipairs(obj.polygon) do
                        min_x = math.min(min_x, obj.x + point.x)
                        min_y = math.min(min_y, obj.y + point.y)
                        max_x = math.max(max_x, obj.x + point.x)
                        max_y = math.max(max_y, obj.y + point.y)
                    end
                else
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
    if not entity.collider then
        entity.collider = self.physicsWorld:newBSGRectangleCollider(
            entity.x, entity.y,
            entity.width, entity.height,
            10
        )
        entity.collider:setFixedRotation(true)
        entity.collider:setCollisionClass("Player")
    end
end

function world:moveEntity(entity, vx, vy, dt)
    if entity.collider then entity.collider:setLinearVelocity(vx, vy) end
end

function world:loadEnemies()
    if self.map.layers["Enemies"] then
        local enemy_module = require "entities.enemy.init"

        for _, obj in ipairs(self.map.layers["Enemies"].objects) do
            local new_enemy = enemy_module:new(obj.x, obj.y, obj.properties.type or "green_slime")

            new_enemy.world = self

            if obj.properties.patrol_points then
                local points = {}
                for point_str in string.gmatch(obj.properties.patrol_points, "([^;]+)") do
                    local x, y = point_str:match("([^,]+),([^,]+)")
                    table.insert(points, {
                        x = obj.x + tonumber(x),
                        y = obj.y + tonumber(y)
                    })
                end
                new_enemy:setPatrolPoints(points)
            else
                new_enemy:setPatrolPoints({
                    { x = obj.x - 50, y = obj.y - 50 },
                    { x = obj.x + 50, y = obj.y - 50 },
                    { x = obj.x + 50, y = obj.y + 50 },
                    { x = obj.x - 50, y = obj.y + 50 }
                })
            end

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

function world:loadNPCs()
    if self.map.layers["NPCs"] then
        local npc_module = require "entities.npc.init"

        for _, obj in ipairs(self.map.layers["NPCs"].objects) do
            local npc_type = obj.properties.type or "villager"
            local npc_id = obj.properties.id or obj.name or ("npc_" .. math.random(10000))

            local new_npc = npc_module:new(obj.x, obj.y, npc_type, npc_id)
            new_npc.world = self

            local bounds = new_npc:getColliderBounds()
            new_npc.collider = self.physicsWorld:newBSGRectangleCollider(
                bounds.x, bounds.y,
                bounds.width, bounds.height,
                8
            )
            new_npc.collider:setFixedRotation(true)
            new_npc.collider:setType("static")         -- NPCs don't move
            new_npc.collider:setCollisionClass("Wall") -- Act as obstacles
            new_npc.collider:setObject(new_npc)

            table.insert(self.npcs, new_npc)
        end

        print("Loaded " .. #self.npcs .. " NPCs")
    end
end

function world:checkLineOfSight(x1, y1, x2, y2)
    local items = self.physicsWorld:queryLine(x1, y1, x2, y2)

    for _, item in ipairs(items) do
        if item.collision_class == "Wall" then
            return false
        end
    end

    return true
end

function world:addEnemy(enemy)
    local bounds = enemy:getColliderBounds()
    enemy.collider = self.physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    enemy.collider:setFixedRotation(true)
    enemy.collider:setCollisionClass("Enemy")
    enemy.collider:setObject(enemy)

    table.insert(self.enemies, enemy)
end

function world:checkWeaponCollisions(weapon)
    local hit_results = {}

    if not weapon:canDealDamage() then
        return hit_results
    end

    for _, enemy in ipairs(self.enemies) do
        if enemy.state ~= "dead" and weapon:checkHit(enemy) then
            table.insert(hit_results, {
                enemy = enemy,
                damage = weapon:getDamage(),
                knockback = weapon:getKnockback()
            })
        end
    end

    return hit_results
end

function world:applyWeaponHit(hit_result)
    local enemy = hit_result.enemy
    local damage = hit_result.damage
    local knockback = hit_result.knockback

    enemy:takeDamage(damage)

    local hit_x = enemy.x + enemy.collider_offset_x
    local hit_y = enemy.y + enemy.collider_offset_y

    local weapon_angle = nil
    if self.player and self.player.weapon then
        weapon_angle = self.player.weapon.angle
    end

    effects:spawnHitEffect(hit_x, hit_y, "enemy", weapon_angle)
end

function world:updateEnemies(dt, player_x, player_y)
    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]

        if enemy.state == "dead" then
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
                enemy.x = enemy.collider:getX() - enemy.collider_offset_x
                enemy.y = enemy.collider:getY() - enemy.collider_offset_y
            end
        end
    end
end

function world:updateNPCs(dt, player_x, player_y)
    for _, npc in ipairs(self.npcs) do
        npc:update(dt, player_x, player_y)
    end
end

function world:drawEnemies()
    for _, enemy in ipairs(self.enemies) do
        enemy:draw()
    end
end

function world:drawNPCs()
    for _, npc in ipairs(self.npcs) do
        npc:draw()
    end
end

function world:drawLayer(layer_name)
    local layer = self.map.layers[layer_name]
    if layer then self.map:drawLayer(layer) end
end

function world:drawDebug()
    self.physicsWorld:draw()

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

    -- Draw NPC debug info
    for _, npc in ipairs(self.npcs) do
        npc:drawDebug()
    end
end

function world:getInteractableNPC(player_x, player_y)
    for _, npc in ipairs(self.npcs) do
        if npc.can_interact then
            return npc
        end
    end
    return nil
end

return world

-- systems/world.lua
-- Manages map loading, rendering, and collision system integration with effects

local sti = require "vendor.sti"
local windfield = require "vendor.windfield"
local effects = require "systems.effects"
local game_mode = require "systems.game_mode"

local world = {}
world.__index = world

function world:new(map_path)
    local instance = setmetatable({}, world)

    local map_info = love.filesystem.getInfo(map_path)
    if not map_info then
        error("Map file not found: " .. map_path)
    end

    instance.map = sti(map_path)

    -- Read game mode from map properties
    local mode = "topdown" -- default
    if instance.map.properties and instance.map.properties.game_mode then
        mode = instance.map.properties.game_mode
    end

    -- Set game mode
    game_mode:set(mode)
    instance.game_mode = mode

    -- Get gravity based on game mode
    local gx, gy = game_mode:getGravity()
    instance.physicsWorld = windfield.newWorld(gx, gy, true)

    print("World created with mode: " .. mode .. " (gravity: " .. gx .. ", " .. gy .. ")")

    instance.physicsWorld:addCollisionClass("Player")
    instance.physicsWorld:addCollisionClass("PlayerDodging")
    instance.physicsWorld:addCollisionClass("Wall")
    instance.physicsWorld:addCollisionClass("Portals")
    instance.physicsWorld:addCollisionClass("Enemy")
    instance.physicsWorld:addCollisionClass("Item")

    instance.physicsWorld.collision_classes.PlayerDodging.ignores = { "Enemy" }

    instance.physicsWorld:collisionClassesSet()

    instance.walls = {}
    instance:loadWalls()

    instance:loadTransitions()

    instance.enemies = {}
    instance:loadEnemies()

    instance.npcs = {}
    instance:loadNPCs()

    instance.savepoints = {}
    instance:loadSavePoints()

    instance.healing_points = {}
    instance:loadHealingPoints()

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

function world:loadWalls()
    if not self.map.layers["Walls"] then return end

    local wall_count = 0
    local rect_count = 0
    local polygon_count = 0
    local polyline_count = 0
    local ellipse_count = 0
    local failed_count = 0

    for i, obj in ipairs(self.map.layers["Walls"].objects) do
        local wall
        local success = true

        if obj.shape == "rectangle" then
            wall = self.physicsWorld:newRectangleCollider(obj.x, obj.y, obj.width, obj.height)
            rect_count = rect_count + 1
        elseif obj.shape == "polygon" and obj.polygon then
            print(string.format("Loading polygon #%d at obj pos (%.1f, %.1f)", i, obj.x, obj.y))
            print(string.format("  Polygon has %d points", #obj.polygon))

            local vertices = {}
            for pi, point in ipairs(obj.polygon) do
                table.insert(vertices, point.x)
                table.insert(vertices, point.y)
                if pi <= 3 then
                    print(string.format("  Point %d: world(%.1f,%.1f)", pi, point.x, point.y))
                end
            end

            print(string.format("  Total vertices array length: %d", #vertices))

            success, wall = pcall(self.physicsWorld.newPolygonCollider, self.physicsWorld, vertices, {
                body_type = 'static',
                collision_class = 'Wall'
            })

            if success then
                polygon_count = polygon_count + 1
            else
                print("Error creating polygon collider #" .. i .. ": " .. tostring(wall))
                failed_count = failed_count + 1
                wall = nil
            end
        elseif obj.shape == "polyline" and obj.polyline then
            local vertices = {}
            for _, point in ipairs(obj.polyline) do
                table.insert(vertices, obj.x + point.x)
                table.insert(vertices, obj.y + point.y)
            end

            success, wall = pcall(self.physicsWorld.newChainCollider, self.physicsWorld, vertices, false, {
                body_type = 'static',
                collision_class = 'Wall'
            })

            if success then
                polyline_count = polyline_count + 1
            else
                print("Error creating polyline collider #" .. i .. ": " .. tostring(wall))
                failed_count = failed_count + 1
                wall = nil
            end
        elseif obj.shape == "ellipse" then
            local radius = math.min(obj.width, obj.height) / 2
            wall = self.physicsWorld:newCircleCollider(
                obj.x + obj.width / 2,
                obj.y + obj.height / 2,
                radius
            )
            ellipse_count = ellipse_count + 1
        end

        if wall then
            wall:setType("static")
            wall:setCollisionClass("Wall")
            wall:setFriction(0.0)  -- No friction for smooth platformer movement
            table.insert(self.walls, wall)
            wall_count = wall_count + 1
        end
    end

    local status = string.format("Loaded %d wall colliders: %d rect, %d polygon, %d polyline, %d ellipse",
        wall_count, rect_count, polygon_count, polyline_count, ellipse_count)

    if failed_count > 0 then
        status = status .. string.format(" (%d FAILED)", failed_count)
    end

    print(status)
end

function world:loadTransitions()
    self.transitions = {}

    if self.map.layers["Portals"] then
        for _, obj in ipairs(self.map.layers["Portals"].objects) do
            if obj.properties.type == "portal" or obj.properties.type == "gameclear" then
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
                    transition_type = obj.properties.type,
                    target_map = obj.properties.target_map,
                    spawn_x = obj.properties.spawn_x or 100,
                    spawn_y = obj.properties.spawn_y or 100
                })
            end
        end
    end
end

function world:loadSavePoints()
    if self.map.layers["SavePoints"] then
        for _, obj in ipairs(self.map.layers["SavePoints"].objects) do
            if obj.properties.type == "savepoint" then
                local center_x = obj.x + obj.width / 2
                local center_y = obj.y + obj.height / 2

                table.insert(self.savepoints, {
                    x = obj.x,
                    y = obj.y,
                    width = obj.width,
                    height = obj.height,
                    center_x = center_x,
                    center_y = center_y,
                    id = obj.properties.id or ("savepoint_" .. #self.savepoints + 1),
                    interaction_range = 80,
                    can_interact = false
                })
            end
        end
        print("Loaded " .. #self.savepoints .. " save points")
    end
end

function world:updateSavePoints(player_x, player_y)
    for _, savepoint in ipairs(self.savepoints) do
        local dx = player_x - savepoint.center_x
        local dy = player_y - savepoint.center_y
        local distance = math.sqrt(dx * dx + dy * dy)

        savepoint.can_interact = (distance < savepoint.interaction_range)
    end
end

function world:getInteractableSavePoint()
    for _, savepoint in ipairs(self.savepoints) do
        if savepoint.can_interact then return savepoint end
    end

    return nil
end

function world:drawSavePoints()
    for _, savepoint in ipairs(self.savepoints) do
        if savepoint.can_interact then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.circle("line", savepoint.center_x, savepoint.center_y - 30, 20)
            love.graphics.print("F", savepoint.center_x - 5, savepoint.center_y - 35)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
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

        -- Reduce friction for better platformer feel
        entity.collider:setFriction(0.0)  -- No friction to prevent wall sliding issues

        -- Platformer grounded detection using PreSolve (called every frame during contact)
        entity.collider:setPreSolve(function(collider_1, collider_2, contact)
            if entity.game_mode == "platformer" then
                local nx, ny = contact:getNormal()

                -- Check both normal directions (collision order is not guaranteed)
                -- If normal is mostly vertical (player on top or bottom of object)
                if math.abs(ny) > 0.7 then
                    local _, vy = entity.collider:getLinearVelocity()

                    -- Player is on ground if:
                    -- 1. Normal points up (ny < 0) OR
                    -- 2. Normal points down (ny > 0) AND player is falling (vy > 0)
                    if ny < 0 or (ny > 0 and vy >= 0) then
                        entity.is_grounded = true
                        entity.can_jump = true
                        entity.is_jumping = false
                    end
                end
            end
        end)
    end
end

function world:moveEntity(entity, vx, vy, dt)
    if not entity.collider then return end

    -- In platformer mode, only set horizontal velocity (gravity handles vertical)
    if entity.game_mode == "platformer" then
        local current_vx, current_vy = entity.collider:getLinearVelocity()

        -- Dodge: direct velocity setting for responsive dodge movement (ignores gravity temporarily)
        if entity.dodge_active then
            entity.collider:setLinearVelocity(vx, current_vy)
        -- Air control: use smoother velocity change when in air
        elseif not entity.is_grounded then
            -- Apply horizontal force instead of directly setting velocity for better air control
            local target_vx = vx
            local force_x = (target_vx - current_vx) * entity.collider:getMass() * 15 -- Air control multiplier
            entity.collider:applyLinearImpulse(force_x * dt, 0)

            -- Clamp horizontal velocity to prevent excessive speed
            local new_vx, new_vy = entity.collider:getLinearVelocity()
            local max_air_speed = entity.speed * 1.2  -- Allow slightly faster air movement
            if math.abs(new_vx) > max_air_speed then
                local sign = new_vx >= 0 and 1 or -1
                entity.collider:setLinearVelocity(sign * max_air_speed, new_vy)
            end
        else
            -- Ground control: direct velocity setting for responsive ground movement
            entity.collider:setLinearVelocity(vx, current_vy)
        end
    else
        -- Topdown mode: set both velocities
        entity.collider:setLinearVelocity(vx, vy)
    end
end

function world:loadEnemies()
    if self.map.layers["Enemies"] then
        local enemy_module = require "entities.enemy"

        for _, obj in ipairs(self.map.layers["Enemies"].objects) do
            local new_enemy = enemy_module:new(obj.x, obj.y, obj.properties.type or "green_slime")

            new_enemy.world = self

            if obj.properties.patrol_points then
                local points = {}
                for point_str in string.gmatch(obj.properties.patrol_points, "([^;]+)") do
                    local x, y = point_str:match("([^,]+),([^,]+)")
                    table.insert(points, { x = obj.x + tonumber(x), y = obj.y + tonumber(y) })
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
        local npc_module = require "entities.npc"

        for _, obj in ipairs(self.map.layers["NPCs"].objects) do
            local npc_type = obj.properties.type or "villager"
            local npc_id = obj.properties.id or obj.name or ("npc_" .. math.random(10000))

            local new_npc = npc_module:new(obj.x, obj.y, npc_type, npc_id)
            new_npc.world = self

            local bounds = new_npc:getColliderBounds()
            new_npc.collider = self.physicsWorld:newBSGRectangleCollider(
                bounds.x - (bounds.width / 2), bounds.y - (bounds.height / 2),
                bounds.width, bounds.height,
                8
            )
            new_npc.collider:setFixedRotation(true)
            new_npc.collider:setType("static")
            new_npc.collider:setCollisionClass("Wall")
            new_npc.collider:setObject(new_npc)

            table.insert(self.npcs, new_npc)
        end

        print("Loaded " .. #self.npcs .. " NPCs")
    end
end

function world:checkLineOfSight(x1, y1, x2, y2)
    local items = self.physicsWorld:queryLine(x1, y1, x2, y2)

    for _, item in ipairs(items) do
        if item.collision_class == "Wall" then return false end
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

    if not weapon:canDealDamage() then return hit_results end

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
                if enemy.collider then enemy.collider:destroy() end
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

    self:updateSavePoints(player_x, player_y)
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

function world:drawEntitiesYSorted(player)
    local drawables = {}

    -- Collect all entities
    table.insert(drawables, player)

    for _, enemy in ipairs(self.enemies) do
        table.insert(drawables, enemy)
    end

    for _, npc in ipairs(self.npcs) do
        table.insert(drawables, npc)
    end

    -- Sort by Y coordinate (foot position for accurate depth)
    table.sort(drawables, function(a, b)
        local a_y = a.y
        local b_y = b.y

        -- Use foot position if collider info is available
        if a.collider_offset_y and a.collider_height then
            a_y = a_y + a.collider_offset_y + a.collider_height / 2
        end
        if b.collider_offset_y and b.collider_height then
            b_y = b_y + b.collider_offset_y + b.collider_height / 2
        end

        return a_y < b_y
    end)

    -- Draw in sorted order
    for _, entity in ipairs(drawables) do
        if entity == player then
            entity:drawAll()
        else
            entity:draw()
        end
    end
end

function world:drawLayer(layer_name)
    local layer = self.map.layers[layer_name]
    if layer then self.map:drawLayer(layer) end
end

function world:drawDebug()
    if not self.physicsWorld then return end
    local success, err = pcall(function() self.physicsWorld:draw() end)
    if not success then return end

    if self.transitions then
        for _, transition in ipairs(self.transitions) do
            if transition.transition_type == "gameclear" then
                love.graphics.setColor(1, 1, 0, 0.3)
            else
                love.graphics.setColor(0, 1, 0, 0.3)
            end
            love.graphics.rectangle("fill", transition.x, transition.y, transition.width, transition.height)

            if transition.transition_type == "gameclear" then
                love.graphics.setColor(1, 1, 0, 1)
            else
                love.graphics.setColor(0, 1, 0, 1)
            end
            love.graphics.rectangle("line", transition.x, transition.y, transition.width, transition.height)
        end
    end

    if self.savepoints then
        for _, savepoint in ipairs(self.savepoints) do
            love.graphics.setColor(0, 0.5, 1, 0.3)
            love.graphics.rectangle("fill", savepoint.x, savepoint.y, savepoint.width, savepoint.height)
            love.graphics.setColor(0, 0.5, 1, 1)
            love.graphics.rectangle("line", savepoint.x, savepoint.y, savepoint.width, savepoint.height)
            love.graphics.print("SAVE", savepoint.x + 5, savepoint.y + 5)

            love.graphics.setColor(0, 1, 1, 0.3)
            love.graphics.circle("line", savepoint.center_x, savepoint.center_y, savepoint.interaction_range)
        end
    end

    if self.npcs then
        for _, npc in ipairs(self.npcs) do
            if npc and npc.drawDebug then npc:drawDebug() end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function world:getInteractableNPC(player_x, player_y)
    for _, npc in ipairs(self.npcs) do
        if npc.can_interact then return npc end
    end

    return nil
end

function world:loadHealingPoints()
    local healing_point_class = require "entities.healing_point"

    if self.map.layers["HealingPoints"] then
        for _, obj in ipairs(self.map.layers["HealingPoints"].objects) do
            if obj.properties.type == "healing_point" or obj.name == "healing_point" then
                local center_x = obj.x + obj.width / 2
                local center_y = obj.y + obj.height / 2

                local heal_amount = obj.properties.heal_amount or 50
                local radius = obj.properties.radius or math.max(obj.width, obj.height) / 2
                local cooldown = obj.properties.cooldown or 5.0

                local hp = healing_point_class:new(center_x, center_y, heal_amount, radius)
                hp.cooldown_max = cooldown

                table.insert(self.healing_points, hp)
            end
        end
        print("Loaded " .. #self.healing_points .. " healing points from map")
    else
        print("No HealingPoints layer found in map")
    end
end

function world:updateHealingPoints(dt, player)
    for _, hp in ipairs(self.healing_points) do
        hp:update(dt, player)
    end
end

function world:drawHealingPoints()
    for _, hp in ipairs(self.healing_points) do
        hp:draw()
    end
end

function world:drawHealingPointsDebug()
    for _, hp in ipairs(self.healing_points) do
        hp:drawDebug()
    end
end

return world

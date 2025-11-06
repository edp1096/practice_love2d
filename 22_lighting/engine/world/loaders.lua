-- systems/world/loaders.lua
-- Contains all loading functions for map objects

local loaders = {}

function loaders.loadWalls(self)
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
            local vertices = {}
            for pi, point in ipairs(obj.polygon) do
                table.insert(vertices, point.x)
                table.insert(vertices, point.y)
            end

            success, wall = pcall(self.physicsWorld.newPolygonCollider, self.physicsWorld, vertices, {
                body_type = 'static',
                collision_class = 'Wall'
            })

            if success then
                polygon_count = polygon_count + 1
            else
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

    -- Wall loading complete (silent)
end

function loaders.loadTransitions(self)
    self.transitions = {}

    if self.map.layers["Portals"] then
        for _, obj in ipairs(self.map.layers["Portals"].objects) do
            if obj.properties.type == "portal" or obj.properties.type == "gameclear" or obj.properties.type == "intro" or obj.properties.type == "ending" then
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
                    spawn_y = obj.properties.spawn_y or 100,
                    intro_id = obj.properties.intro_id
                })
            end
        end
    end
end

function loaders.loadSavePoints(self)
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
    end
end

function loaders.loadEnemies(self)
    if self.map.layers["Enemies"] then
        local enemy_module = require "game.entities.enemy"

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

            -- Platformer mode: remove air resistance for faster falling
            if self.game_mode == "platformer" then
                new_enemy.collider:setLinearDamping(0)
                -- Also set gravity scale to ensure full gravity effect
                new_enemy.collider:setGravityScale(1)
                -- Get the underlying Box2D body and set damping there too
                local body = new_enemy.collider.body
                if body then
                    body:setLinearDamping(0)
                end
            end

            table.insert(self.enemies, new_enemy)
        end
    end
end

function loaders.loadNPCs(self)
    if self.map.layers["NPCs"] then
        local npc_module = require "game.entities.npc"

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
            new_npc.collider:setType("static")
            new_npc.collider:setCollisionClass("Wall")
            new_npc.collider:setObject(new_npc)

            -- Update NPC position to match Enemy pattern (x,y = reference point)
            new_npc.x = new_npc.collider:getX() - new_npc.collider_offset_x
            new_npc.y = new_npc.collider:getY() - new_npc.collider_offset_y

            table.insert(self.npcs, new_npc)
        end
    end
end

function loaders.loadHealingPoints(self)
    local healing_point_class = require "game.entities.healing_point"

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
    end
end

function loaders.loadDeathZones(self)
    if not self.map.layers["DeathZones"] then return end

    for _, obj in ipairs(self.map.layers["DeathZones"].objects) do
        local zone

        if obj.shape == "rectangle" then
            zone = self.physicsWorld:newRectangleCollider(obj.x, obj.y, obj.width, obj.height)
        elseif obj.shape == "polygon" and obj.polygon then
            local vertices = {}
            for _, point in ipairs(obj.polygon) do
                table.insert(vertices, point.x)
                table.insert(vertices, point.y)
            end

            local success
            success, zone = pcall(self.physicsWorld.newPolygonCollider, self.physicsWorld, vertices, {
                body_type = 'static',
                collision_class = 'DeathZone'
            })

            if not success then
                zone = nil
            end
        elseif obj.shape == "ellipse" then
            local radius = math.min(obj.width, obj.height) / 2
            zone = self.physicsWorld:newCircleCollider(
                obj.x + obj.width / 2,
                obj.y + obj.height / 2,
                radius
            )
        end

        if zone then
            zone:setType("static")
            zone:setCollisionClass("DeathZone")
            zone:setSensor(true)  -- Sensor = no physical collision, only detection
            table.insert(self.death_zones, zone)
        end
    end
end

function loaders.loadDamageZones(self)
    if not self.map.layers["DamageZones"] then
        dprint("DamageZones layer not found!")
        return
    end

    dprint("Loading DamageZones:", #self.map.layers["DamageZones"].objects, "zones found")

    for _, obj in ipairs(self.map.layers["DamageZones"].objects) do
        local zone

        if obj.shape == "rectangle" then
            zone = self.physicsWorld:newRectangleCollider(obj.x, obj.y, obj.width, obj.height)
        elseif obj.shape == "polygon" and obj.polygon then
            local vertices = {}
            for _, point in ipairs(obj.polygon) do
                table.insert(vertices, point.x)
                table.insert(vertices, point.y)
            end

            local success
            success, zone = pcall(self.physicsWorld.newPolygonCollider, self.physicsWorld, vertices, {
                body_type = 'static',
                collision_class = 'DamageZone'
            })

            if not success then
                zone = nil
            end
        elseif obj.shape == "ellipse" then
            local radius = math.min(obj.width, obj.height) / 2
            zone = self.physicsWorld:newCircleCollider(
                obj.x + obj.width / 2,
                obj.y + obj.height / 2,
                radius
            )
        end

        if zone then
            zone:setType("static")
            zone:setCollisionClass("DamageZone")
            zone:setSensor(true)  -- Sensor = no physical collision, only detection

            -- Store zone properties
            zone.damage = obj.properties.damage or 10
            zone.damage_cooldown = obj.properties.cooldown or 1.0  -- Damage interval (seconds)

            table.insert(self.damage_zones, {
                collider = zone,
                damage = zone.damage,
                damage_cooldown = zone.damage_cooldown
            })
            dprint("DamageZone added:", zone.damage, "damage,", zone.damage_cooldown, "cooldown")
        end
    end

    dprint("Total DamageZones loaded:", #self.damage_zones)
end

return loaders

-- engine/systems/collision.lua
-- Centralized collision system for creating and managing colliders

local constants = require "engine.core.constants"

local collision = {}

-- Setup collision classes and ignore rules for physics world
function collision.setupCollisionClasses(physicsWorld, game_mode)
    physicsWorld:addCollisionClass("Player")
    physicsWorld:addCollisionClass("PlayerDodging")
    physicsWorld:addCollisionClass("PlayerFoot")  -- Topdown foot collider
    physicsWorld:addCollisionClass("Wall")
    physicsWorld:addCollisionClass("WallBase")    -- Topdown base surface
    physicsWorld:addCollisionClass("Portals")
    physicsWorld:addCollisionClass("Enemy")
    physicsWorld:addCollisionClass("EnemyFoot")   -- Topdown enemy foot collider
    physicsWorld:addCollisionClass("NPC")
    physicsWorld:addCollisionClass("Item")
    physicsWorld:addCollisionClass("DeathZone")
    physicsWorld:addCollisionClass("DamageZone")

    physicsWorld.collision_classes.PlayerDodging.ignores = { "Enemy", "EnemyFoot" }

    -- Topdown mode: Player and Enemy main colliders ignore each other (only foot colliders collide)
    if game_mode == "topdown" then
        physicsWorld.collision_classes.Player.ignores = { "Enemy" }
        physicsWorld.collision_classes.Enemy.ignores = { "Player" }

        -- PlayerFoot: collides with Wall, WallBase, EnemyFoot, and NPC (topdown needs NPC collision!)
        physicsWorld.collision_classes.PlayerFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "Item", "DeathZone", "DamageZone" }

        -- EnemyFoot: collides with Wall, WallBase, PlayerFoot, and NPC
        physicsWorld.collision_classes.EnemyFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "Item", "DeathZone", "DamageZone" }
    else
        -- Platformer mode: PlayerFoot and EnemyFoot don't exist, Player main collider handles everything
        -- But we still set up the rules in case they're created
        physicsWorld.collision_classes.PlayerFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }
        physicsWorld.collision_classes.EnemyFoot.ignores = { "Player", "PlayerDodging", "Enemy", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }
    end

    -- WallBase only collides with PlayerFoot and EnemyFoot (not with combat or other systems)
    physicsWorld.collision_classes.WallBase.ignores = { "Player", "PlayerDodging", "Enemy", "Wall", "Portals", "NPC", "Item", "DeathZone", "DamageZone" }

    physicsWorld:collisionClassesSet()
end

-- Create colliders for player entity
function collision.createPlayerColliders(player, physicsWorld)
    if player.collider then
        return  -- Already has colliders
    end

    -- Main collider (combat, platformer physics)
    player.collider = physicsWorld:newBSGRectangleCollider(
        player.x, player.y,
        player.collider_width, player.collider_height,
        10
    )
    player.collider:setFixedRotation(true)
    player.collider:setCollisionClass(constants.COLLISION_CLASSES.PLAYER)
    player.collider:setFriction(0.0)  -- No friction for better platformer feel

    -- Topdown mode: Add foot collider (bottom only)
    if player.game_mode == "topdown" then
        local bottom_height = player.collider_height * 0.1875  -- Bottom 18.75% (1.5x of 12.5%)
        local bottom_y_offset = player.collider_height * 0.40625  -- Position at 81.25% down

        player.foot_collider = physicsWorld:newBSGRectangleCollider(
            player.x,
            player.y + bottom_y_offset,
            player.collider_width,
            bottom_height,
            5  -- Smaller corner radius
        )
        player.foot_collider:setFixedRotation(true)
        player.foot_collider:setCollisionClass(constants.COLLISION_CLASSES.PLAYER_FOOT)
        player.foot_collider:setFriction(0.0)
        player.foot_collider:setObject(player)  -- Link back to player
    end

    -- Platformer grounded detection using PreSolve
    player.collider:setPreSolve(function(collider_1, collider_2, contact)
        if player.game_mode == "platformer" then
            local nx, ny = contact:getNormal()

            -- Check if normal is mostly vertical (player on top or bottom of object)
            if math.abs(ny) > 0.7 then
                local _, vy = player.collider:getLinearVelocity()

                -- Player is on ground if normal points up or player is falling
                if ny < 0 or (ny > 0 and vy >= 0) then
                    player.is_grounded = true
                    player.can_jump = true
                    player.is_jumping = false

                    -- Store contact surface Y position for shadow rendering
                    local points = {contact:getPositions()}
                    if #points >= 2 then
                        player.contact_surface_y = points[2]
                    end
                end
            end
        end
    end)
end

-- Create colliders for wall object (returns main wall collider and optional bottom collider)
function collision.createWallColliders(obj, physicsWorld, game_mode)
    local colliders = {}

    -- Shape handlers for different wall types
    local shapeHandlers = {
        rectangle = function(world, object)
            local wall = world:newRectangleCollider(object.x, object.y, object.width, object.height)
            return true, wall
        end,

        polygon = function(world, object)
            if not object.polygon then return false, nil end

            local vertices = {}
            for _, point in ipairs(object.polygon) do
                table.insert(vertices, point.x)
                table.insert(vertices, point.y)
            end

            return pcall(world.newPolygonCollider, world, vertices, {
                body_type = 'static',
                collision_class = 'Wall'
            })
        end,

        polyline = function(world, object)
            if not object.polyline then return false, nil end

            local vertices = {}
            for _, point in ipairs(object.polyline) do
                table.insert(vertices, object.x + point.x)
                table.insert(vertices, object.y + point.y)
            end

            return pcall(world.newChainCollider, world, vertices, false, {
                body_type = 'static',
                collision_class = 'Wall'
            })
        end,

        ellipse = function(world, object)
            local radius = math.min(object.width, object.height) / 2
            local wall = world:newCircleCollider(
                object.x + object.width / 2,
                object.y + object.height / 2,
                radius
            )
            return true, wall
        end
    }

    -- Get shape handler
    local handler = shapeHandlers[obj.shape]
    if not handler then
        print("Warning: Unknown shape type '" .. tostring(obj.shape) .. "' in Walls layer")
        return colliders
    end

    -- Create main wall collider
    local success, wall = handler(physicsWorld, obj)
    if not success or not wall then
        return colliders
    end

    wall:setType("static")
    wall:setCollisionClass(constants.COLLISION_CLASSES.WALL)
    wall:setFriction(0.0)
    table.insert(colliders, wall)

    -- Topdown mode: Create base collider for wall surface
    if game_mode == "topdown" and obj.shape == "rectangle" then
        local bottom_height = math.max(8, obj.height * 0.15)  -- Bottom 15%, min 8px
        local base_collider = physicsWorld:newRectangleCollider(
            obj.x,
            obj.y + obj.height - bottom_height,  -- Position at bottom
            obj.width,
            bottom_height
        )
        base_collider:setType("static")
        base_collider:setCollisionClass(constants.COLLISION_CLASSES.WALL_BASE)
        base_collider:setFriction(0.0)
        table.insert(colliders, base_collider)
    end

    return colliders
end

-- Create collider for enemy entity
function collision.createEnemyCollider(enemy, physicsWorld, game_mode)
    if enemy.collider then
        return  -- Already has colliders
    end

    -- Store game mode for later use
    enemy.game_mode = game_mode

    local bounds = enemy:getColliderBounds()

    -- Main collider (combat, physics)
    enemy.collider = physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    enemy.collider:setFixedRotation(true)
    enemy.collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY)
    enemy.collider:setObject(enemy)

    -- Topdown mode: Add foot collider based on enemy type
    if game_mode == "topdown" then
        if enemy.is_humanoid then
            -- Humanoid enemies: foot collider like player (12.5% height at bottom)
            local bottom_height = enemy.collider_height * 0.125  -- Bottom 12.5%
            local bottom_y_offset = enemy.collider_height * 0.4375  -- Position at 87.5% down

            enemy.foot_collider = physicsWorld:newBSGRectangleCollider(
                bounds.x,
                bounds.y + bottom_y_offset,
                enemy.collider_width,
                bottom_height,
                5  -- Smaller corner radius
            )
            enemy.foot_collider:setFixedRotation(true)
            enemy.foot_collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY_FOOT)
            enemy.foot_collider:setFriction(0.0)
            enemy.foot_collider:setObject(enemy)  -- Link back to enemy
        else
            -- Slime enemies: bottom 60% collision (no visible feet)
            local bottom_height = enemy.collider_height * 0.6  -- Bottom 60%
            local bottom_y_offset = enemy.collider_height * 0.2  -- Position at 40% down

            enemy.foot_collider = physicsWorld:newBSGRectangleCollider(
                bounds.x,
                bounds.y + bottom_y_offset,
                enemy.collider_width,
                bottom_height,
                5
            )
            enemy.foot_collider:setFixedRotation(true)
            enemy.foot_collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY_FOOT)
            enemy.foot_collider:setFriction(0.0)
            enemy.foot_collider:setObject(enemy)
        end
    end

    -- Platformer mode: remove air resistance for faster falling
    if game_mode == "platformer" then
        enemy.collider:setLinearDamping(0)
        enemy.collider:setGravityScale(1)

        local body = enemy.collider.body
        if body then
            body:setLinearDamping(0)
        end
    end
end

-- Create collider for NPC entity
function collision.createNPCCollider(npc, physicsWorld, game_mode)
    local bounds = npc:getColliderBounds()
    npc.collider = physicsWorld:newBSGRectangleCollider(
        bounds.x, bounds.y,
        bounds.width, bounds.height,
        8
    )
    npc.collider:setFixedRotation(true)
    npc.collider:setType("static")
    npc.collider:setCollisionClass(constants.COLLISION_CLASSES.NPC)
    npc.collider:setObject(npc)

    -- Platformer: Make NPC a sensor (no physical collision, only detection)
    -- Prevents player from standing on NPC like a platform
    if game_mode == "platformer" then
        npc.collider:setSensor(true)
    end

    -- Update NPC position to match collider
    npc.x = npc.collider:getX() - npc.collider_offset_x
    npc.y = npc.collider:getY() - npc.collider_offset_y
end

-- Create collider for death zone (returns collider or nil)
function collision.createDeathZoneCollider(obj, physicsWorld)
    local zone

    if obj.shape == "rectangle" then
        zone = physicsWorld:newRectangleCollider(obj.x, obj.y, obj.width, obj.height)
    elseif obj.shape == "polygon" and obj.polygon then
        local vertices = {}
        for _, point in ipairs(obj.polygon) do
            table.insert(vertices, point.x)
            table.insert(vertices, point.y)
        end

        local success
        success, zone = pcall(physicsWorld.newPolygonCollider, physicsWorld, vertices, {
            body_type = 'static',
            collision_class = 'DeathZone'
        })

        if not success then
            zone = nil
        end
    elseif obj.shape == "ellipse" then
        local radius = math.min(obj.width, obj.height) / 2
        zone = physicsWorld:newCircleCollider(
            obj.x + obj.width / 2,
            obj.y + obj.height / 2,
            radius
        )
    end

    if zone then
        zone:setType("static")
        zone:setCollisionClass("DeathZone")
        zone:setSensor(true)  -- Sensor = no physical collision, only detection
    end

    return zone
end

-- Create collider for damage zone (returns zone data with collider and properties, or nil)
function collision.createDamageZoneCollider(obj, physicsWorld)
    local zone

    if obj.shape == "rectangle" then
        zone = physicsWorld:newRectangleCollider(obj.x, obj.y, obj.width, obj.height)
    elseif obj.shape == "polygon" and obj.polygon then
        local vertices = {}
        for _, point in ipairs(obj.polygon) do
            table.insert(vertices, point.x)
            table.insert(vertices, point.y)
        end

        local success
        success, zone = pcall(physicsWorld.newPolygonCollider, physicsWorld, vertices, {
            body_type = 'static',
            collision_class = 'DamageZone'
        })

        if not success then
            zone = nil
        end
    elseif obj.shape == "ellipse" then
        local radius = math.min(obj.width, obj.height) / 2
        zone = physicsWorld:newCircleCollider(
            obj.x + obj.width / 2,
            obj.y + obj.height / 2,
            radius
        )
    end

    if zone then
        zone:setType("static")
        zone:setCollisionClass("DamageZone")
        zone:setSensor(true)

        -- Store zone properties
        zone.damage = obj.properties.damage or 10
        zone.damage_cooldown = obj.properties.cooldown or 1.0

        return {
            collider = zone,
            damage = zone.damage,
            damage_cooldown = zone.damage_cooldown
        }
    end

    return nil
end

return collision

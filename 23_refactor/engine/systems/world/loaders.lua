-- systems/world/loaders.lua
-- Contains all loading functions for map objects

local factory = require "engine.entities.factory"
local constants = require "engine.core.constants"

local loaders = {}

-- Shape handlers for wall creation
local shapeHandlers = {
    rectangle = function(physicsWorld, obj)
        local wall = physicsWorld:newRectangleCollider(obj.x, obj.y, obj.width, obj.height)
        return true, wall
    end,

    polygon = function(physicsWorld, obj)
        if not obj.polygon then return false, nil end

        local vertices = {}
        for _, point in ipairs(obj.polygon) do
            table.insert(vertices, point.x)
            table.insert(vertices, point.y)
        end

        return pcall(physicsWorld.newPolygonCollider, physicsWorld, vertices, {
            body_type = 'static',
            collision_class = 'Wall'
        })
    end,

    polyline = function(physicsWorld, obj)
        if not obj.polyline then return false, nil end

        local vertices = {}
        for _, point in ipairs(obj.polyline) do
            table.insert(vertices, obj.x + point.x)
            table.insert(vertices, obj.y + point.y)
        end

        return pcall(physicsWorld.newChainCollider, physicsWorld, vertices, false, {
            body_type = 'static',
            collision_class = 'Wall'
        })
    end,

    ellipse = function(physicsWorld, obj)
        local radius = math.min(obj.width, obj.height) / 2
        local wall = physicsWorld:newCircleCollider(
            obj.x + obj.width / 2,
            obj.y + obj.height / 2,
            radius
        )
        return true, wall
    end
}

function loaders.loadTreeTiles(self)
    if not self.map.layers["Trees"] then return end

    -- Initialize drawable tiles array for Y-sorting
    if not self.drawable_tiles then
        self.drawable_tiles = {}
    end

    local layer = self.map.layers["Trees"]
    local tile_width = self.map.tilewidth
    local tile_height = self.map.tileheight

    -- Iterate through all tiles in the layer
    for y = 1, layer.height do
        for x = 1, layer.width do
            local tile_data = layer.data[y] and layer.data[y][x]
            if tile_data and tile_data.gid and tile_data.gid > 0 then
                -- Get tile info from map's tiles table
                local tile_info = self.map.tiles[tile_data.gid]
                if not tile_info then
                    goto continue
                end

                -- Get tileset
                local tileset = self.map.tilesets[tile_info.tileset]
                if not tileset or not tileset.image then
                    goto continue
                end

                -- Calculate world position
                local world_x = (x - 1) * tile_width
                local world_y = (y - 1) * tile_height

                -- Add to drawable tiles for Y-sorting
                table.insert(self.drawable_tiles, {
                    x = world_x,
                    y = world_y + tile_height,  -- Bottom Y for sorting
                    tile_info = tile_info,
                    tileset = tileset,
                    world_x = world_x,
                    world_y = world_y,
                    draw = function(self_tile)
                        -- Draw the tile using tileset image and quad
                        love.graphics.draw(
                            self_tile.tileset.image,
                            self_tile.tile_info.quad,
                            self_tile.world_x,
                            self_tile.world_y
                        )
                    end
                })

                ::continue::
            end
        end
    end
end

function loaders.loadWalls(self)
    if not self.map.layers["Walls"] then return end

    -- Initialize drawable walls array for Y-sorting
    if not self.drawable_walls then
        self.drawable_walls = {}
    end

    for _, obj in ipairs(self.map.layers["Walls"].objects) do
        -- Get shape handler
        local handler = shapeHandlers[obj.shape]
        if not handler then
            print("Warning: Unknown shape type '" .. tostring(obj.shape) .. "' in Walls layer")
            goto continue
        end

        -- Create main wall collider (combat, platformer physics)
        local success, wall = handler(self.physicsWorld, obj)

        if success and wall then
            wall:setType("static")
            wall:setCollisionClass(constants.COLLISION_CLASSES.WALL)
            wall:setFriction(0.0)  -- No friction for smooth platformer movement
            table.insert(self.walls, wall)

            -- Topdown mode: Create bottom collider for wall surface + drawable for Y-sorting
            if self.game_mode == "topdown" and obj.shape == "rectangle" then
                local bottom_height = math.max(8, obj.height * 0.15)  -- Bottom 15%, min 8px
                local bottom_collider = self.physicsWorld:newRectangleCollider(
                    obj.x,
                    obj.y + obj.height - bottom_height,  -- Position at bottom
                    obj.width,
                    bottom_height
                )
                bottom_collider:setType("static")
                bottom_collider:setCollisionClass(constants.COLLISION_CLASSES.WALL_MOVEMENT)
                bottom_collider:setFriction(0.0)

                -- Store reference for cleanup
                table.insert(self.walls, bottom_collider)

                -- Add drawable wall data for Y-sorting (use bottom Y position)
                table.insert(self.drawable_walls, {
                    x = obj.x,
                    y = obj.y + obj.height,  -- Bottom Y position for sorting
                    width = obj.width,
                    height = obj.height,
                    full_y = obj.y,  -- Top Y position for drawing
                    draw = function(self)
                        -- Draw nothing (graphics are in tile layer)
                        -- This is just for Y-sorting
                    end
                })
            end
        end

        ::continue::
    end
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
                    -- Handle rotation (Tiled rotates objects around their origin)
                    local rotation = obj.rotation or 0
                    if rotation == 90 or rotation == -270 then
                        -- 90° clockwise: width and height swap, x shifts
                        min_x = obj.x - obj.height
                        min_y = obj.y
                        max_x = obj.x
                        max_y = obj.y + obj.width
                    elseif rotation == 180 or rotation == -180 then
                        -- 180°: object flips
                        min_x = obj.x - obj.width
                        min_y = obj.y - obj.height
                        max_x = obj.x
                        max_y = obj.y
                    elseif rotation == 270 or rotation == -90 then
                        -- 270° clockwise (90° counter-clockwise): width and height swap, y shifts
                        min_x = obj.x
                        min_y = obj.y - obj.width
                        max_x = obj.x + obj.height
                        max_y = obj.y
                    else
                        -- No rotation or unsupported rotation
                        max_x = obj.x + obj.width
                        max_y = obj.y + obj.height
                    end
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
    if not self.enemy_class then
        print("Warning: No enemy_class injected, skipping enemy loading")
        return
    end

    if self.map.layers["Enemies"] then
        for _, obj in ipairs(self.map.layers["Enemies"].objects) do
            -- Use factory to create from Tiled properties
            local new_enemy = factory:createEnemy(obj, self.enemy_class)

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
            new_enemy.collider:setCollisionClass(constants.COLLISION_CLASSES.ENEMY)
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
    if not self.npc_class then
        print("Warning: No npc_class injected, skipping NPC loading")
        return
    end

    if self.map.layers["NPCs"] then
        for _, obj in ipairs(self.map.layers["NPCs"].objects) do
            -- Use factory to create from Tiled properties
            local new_npc = factory:createNPC(obj, self.npc_class)
            new_npc.world = self

            local bounds = new_npc:getColliderBounds()
            new_npc.collider = self.physicsWorld:newBSGRectangleCollider(
                bounds.x, bounds.y,
                bounds.width, bounds.height,
                8
            )
            new_npc.collider:setFixedRotation(true)
            new_npc.collider:setType("static")
            new_npc.collider:setCollisionClass(constants.COLLISION_CLASSES.WALL)
            new_npc.collider:setObject(new_npc)

            -- Update NPC position to match Enemy pattern (x,y = reference point)
            new_npc.x = new_npc.collider:getX() - new_npc.collider_offset_x
            new_npc.y = new_npc.collider:getY() - new_npc.collider_offset_y

            table.insert(self.npcs, new_npc)
        end
    end
end

function loaders.loadHealingPoints(self)
    if not self.healing_point_class then
        print("Warning: No healing_point_class injected, skipping healing point loading")
        return
    end

    if self.map.layers["HealingPoints"] then
        for _, obj in ipairs(self.map.layers["HealingPoints"].objects) do
            if obj.properties.type == "healing_point" or obj.name == "healing_point" then
                local center_x = obj.x + obj.width / 2
                local center_y = obj.y + obj.height / 2

                local heal_amount = obj.properties.heal_amount or 50
                local radius = obj.properties.radius or math.max(obj.width, obj.height) / 2
                local cooldown = obj.properties.cooldown or 5.0

                local hp = self.healing_point_class:new(center_x, center_y, heal_amount, radius)
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
        return
    end

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
        end
    end
end

return loaders

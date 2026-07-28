-- systems/world/loaders.lua
-- Contains all loading functions for map objects

local factory = require "engine.systems.entity_factory"
local constants = require "engine.core.constants"
local collision = require "engine.systems.collision"
local geometry = require "engine.utils.geometry"

local loaders = {}

-- Constants
local DEFAULT_PATROL_OFFSET = 50

-- Helper functions for enemy/NPC loading

-- Check if enemy should be spawned (not killed, not transformed)
local function shouldSpawnEnemy(map_id, killed_enemies, transformed_npcs)
    local is_killed = killed_enemies[map_id]
    local is_transformed = transformed_npcs and transformed_npcs[map_id]
    return not is_killed and not is_transformed
end

-- Parse patrol points from Tiled object properties
local function parsePatrolPoints(obj)
    if not obj.properties.patrol_points then
        return nil
    end

    local points = {}
    for point_str in string.gmatch(obj.properties.patrol_points, "([^;]+)") do
        local x, y = point_str:match("([^,]+),([^,]+)")
        table.insert(points, {
            x = obj.x + tonumber(x),
            y = obj.y + tonumber(y)
        })
    end
    return points
end

-- Get default patrol points around object position
local function getDefaultPatrolPoints(x, y)
    return {
        { x = x - DEFAULT_PATROL_OFFSET, y = y - DEFAULT_PATROL_OFFSET },
        { x = x + DEFAULT_PATROL_OFFSET, y = y - DEFAULT_PATROL_OFFSET },
        { x = x + DEFAULT_PATROL_OFFSET, y = y + DEFAULT_PATROL_OFFSET },
        { x = x - DEFAULT_PATROL_OFFSET, y = y + DEFAULT_PATROL_OFFSET }
    }
end

-- Check if transformed enemy should be loaded
local function shouldLoadTransformedEnemy(transform_data, current_map_name, map_id, killed_enemies)
    local is_same_map = transform_data.map_name == current_map_name
    local is_enemy_transform = transform_data.enemy_type ~= nil
    local is_alive = not killed_enemies[map_id]

    return is_same_map and is_enemy_transform and is_alive
end

-- Check if transformed NPC should be loaded
local function shouldLoadTransformedNPC(npc_data, current_map_name)
    local is_same_map = npc_data.map_name == current_map_name
    local has_npc_type = npc_data.npc_type ~= nil
    local not_enemy = not npc_data.enemy_type  -- Skip NPC→Enemy transforms

    return is_same_map and has_npc_type and not_enemy
end

-- Check if original NPC should spawn (not transformed, not killed)
local function shouldSpawnOriginalNPC(map_id, killed_enemies, transformed_npcs)
    -- Skip if NPC was transformed to enemy
    if transformed_npcs and transformed_npcs[map_id] and transformed_npcs[map_id].enemy_type then
        return false
    end
    -- Skip if NPC was killed
    if killed_enemies and killed_enemies[map_id] then
        return false
    end
    return true
end

-- Helper: Check if a point is inside any stair area (uses geometry utilities)
local function isInStairArea(stairs, x, y)
    return geometry.pointInZones(stairs, x, y)
end

-- Helper: Create a drawable tile object
local function createDrawableTile(tile_info, tileset, world_x, world_y, tile_height, gid, map)
    return {
        x = world_x,
        y = world_y + tile_height,  -- Bottom Y for sorting
        tile_info = tile_info,
        tileset = tileset,
        world_x = world_x,
        world_y = world_y,
        gid = gid,
        map = map,
        draw = function(self_tile)
            local current_tile = self_tile.map.tiles[self_tile.gid]
            local quad = self_tile.tile_info.quad

            if current_tile and current_tile.animation then
                local frame_tileid = current_tile.animation[current_tile.frame].tileid
                local frame_gid = frame_tileid + self_tile.map.tilesets[current_tile.tileset].firstgid
                local frame_tile = self_tile.map.tiles[frame_gid]
                if frame_tile then
                    quad = frame_tile.quad
                end
            end

            love.graphics.draw(
                self_tile.tileset.image,
                quad,
                self_tile.world_x,
                self_tile.world_y
            )
        end
    }
end

-- Helper: Process a single tile for loading
local function processTile(self, tile_data, world_x, world_y, tile_width, tile_height)
    if not (tile_data and tile_data.gid and tile_data.gid > 0) then return end

    local tile_info = self.map.tiles[tile_data.gid]
    if not tile_info then return end

    local tileset = self.map.tilesets[tile_info.tileset]
    if not (tileset and tileset.image) then return end

    local drawable = createDrawableTile(
        tile_info, tileset, world_x, world_y,
        tile_height, tile_data.gid, self.map
    )

    -- Check if tile is in stair area
    local tile_center_x = world_x + tile_width / 2
    local tile_center_y = world_y + tile_height / 2

    if isInStairArea(self.stairs, tile_center_x, tile_center_y) then
        table.insert(self.stair_tiles, drawable)
    else
        table.insert(self.drawable_tiles, drawable)
    end
end

function loaders.loadTreeTiles(self)
    if not self.map.layers["Decos"] then return end

    self.drawable_tiles = self.drawable_tiles or {}
    self.stair_tiles = self.stair_tiles or {}

    local layer = self.map.layers["Decos"]
    local tile_width = self.map.tilewidth
    local tile_height = self.map.tileheight

    for y = 1, layer.height do
        for x = 1, layer.width do
            local tile_data = layer.data[y] and layer.data[y][x]
            local world_x = (x - 1) * tile_width
            local world_y = (y - 1) * tile_height
            processTile(self, tile_data, world_x, world_y, tile_width, tile_height)
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
        -- Create wall colliders using collision module
        local colliders = collision.createWallColliders(obj, self.physicsWorld, self.game_mode)

        -- Store all colliders for cleanup
        for _, collider in ipairs(colliders) do
            table.insert(self.walls, collider)
        end

        -- Topdown mode: Add drawable wall data for Y-sorting
        if self.game_mode == "topdown" and obj.shape == "rectangle" and #colliders > 0 then
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

                -- allow_vehicle: defaults to true if not specified
                local allow_vehicle = true
                if obj.properties.allow_vehicle == false then
                    allow_vehicle = false
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
                    intro_id = obj.properties.intro_id,
                    allow_vehicle = allow_vehicle
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

function loaders.loadEnemies(self, killed_enemies)
    if not self.enemy_class then
        return
    end

    killed_enemies = killed_enemies or {}
    local map_name = self.map.properties.name or "unknown"

    -- Load original enemies from Tiled map
    if self.map.layers["Enemies"] then
        for _, obj in ipairs(self.map.layers["Enemies"].objects) do
            local map_id = string.format("%s_obj_%d", map_name, obj.id)

            if shouldSpawnEnemy(map_id, killed_enemies, self.transformed_npcs) then
                -- Create enemy from Tiled properties
                local new_enemy = factory:createEnemy(obj, self.enemy_class, map_name)
                new_enemy.world = self

                -- Setup patrol points (custom or default)
                local patrol_points = parsePatrolPoints(obj) or getDefaultPatrolPoints(obj.x, obj.y)
                new_enemy:setPatrolPoints(patrol_points)

                -- Create collider and add to world
                collision.createEnemyCollider(new_enemy, self.physicsWorld, self.game_mode)
                table.insert(self.enemies, new_enemy)
            end
        end
    end

    -- Load transformed enemies (NPCs that became enemies)
    if self.transformed_npcs then
        local current_map_name = self.map.properties.name or "unknown"
        for map_id, transform_data in pairs(self.transformed_npcs) do
            if shouldLoadTransformedEnemy(transform_data, current_map_name, map_id, killed_enemies) then
                -- Create transformed enemy
                local new_enemy = self.enemy_class:new(transform_data.x, transform_data.y, transform_data.enemy_type)
                new_enemy.direction = transform_data.direction or "down"
                new_enemy.map_id = map_id
                new_enemy.was_npc = true
                new_enemy.respawn = false  -- Transformed enemies don't respawn when killed
                new_enemy.world = self

                -- Setup default patrol points
                local patrol_points = getDefaultPatrolPoints(transform_data.x, transform_data.y)
                new_enemy:setPatrolPoints(patrol_points)

                -- Create collider and add to world
                collision.createEnemyCollider(new_enemy, self.physicsWorld, self.game_mode)
                table.insert(self.enemies, new_enemy)
            end
        end
    end
end

function loaders.loadNPCs(self)
    if not self.npc_class then
        return
    end

    local map_name = self.map.properties.name or "unknown"

    -- Load original NPCs from Tiled map
    if self.map.layers["NPCs"] then
        for _, obj in ipairs(self.map.layers["NPCs"].objects) do
            local map_id = string.format("%s_obj_%d", map_name, obj.id)

            if shouldSpawnOriginalNPC(map_id, self.killed_enemies, self.transformed_npcs) then
                -- Create NPC from Tiled properties
                local new_npc = factory:createNPC(obj, self.npc_class)
                new_npc.map_id = map_id
                new_npc.world = self

                -- Create collider and add to world
                collision.createNPCCollider(new_npc, self.physicsWorld, self.game_mode)
                table.insert(self.npcs, new_npc)
            end
        end
    end

    -- Load transformed NPCs (enemies that became NPCs)
    if self.transformed_npcs then
        local current_map_name = self.map.properties.name or "unknown"
        for map_id, npc_data in pairs(self.transformed_npcs) do
            if shouldLoadTransformedNPC(npc_data, current_map_name) then
                -- Create transformed NPC
                local new_npc = self.npc_class:new(npc_data.x, npc_data.y, npc_data.npc_type)
                local dir = npc_data.direction or "down"
                new_npc.direction = dir
                new_npc.anim = new_npc.animations["idle_" .. dir]  -- Update animation
                new_npc.map_id = map_id
                new_npc.world = self

                -- Create collider and add to world
                collision.createNPCCollider(new_npc, self.physicsWorld, self.game_mode)
                table.insert(self.npcs, new_npc)
            end
        end
    end
end

function loaders.loadHealingPoints(self)
    if not self.healing_point_class then
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
        -- Create death zone collider using collision module
        local zone = collision.createDeathZoneCollider(obj, self.physicsWorld)
        if zone then
            table.insert(self.death_zones, zone)
        end
    end
end

function loaders.loadDamageZones(self)
    if not self.map.layers["DamageZones"] then
        return
    end

    for _, obj in ipairs(self.map.layers["DamageZones"].objects) do
        -- Create damage zone collider using collision module
        local zone_data = collision.createDamageZoneCollider(obj, self.physicsWorld)
        if zone_data then
            table.insert(self.damage_zones, zone_data)
        end
    end
end

function loaders.loadWorldItems(self, picked_items)
    if not self.world_item_class then
        return
    end

    picked_items = picked_items or {}

    if self.map.layers["WorldItems"] then
        for _, obj in ipairs(self.map.layers["WorldItems"].objects) do
            local item_type = obj.properties.item_type
            local quantity = obj.properties.quantity or 1
            -- Only items with explicit respawn=true will respawn
            local respawn = (obj.properties.respawn == true)

            if item_type then
                -- Create unique map_id: "{map_name}_obj_{id}" (e.g., "level1_area1_obj_123")
                local map_name = self.map.properties.name or "unknown"
                local map_id = string.format("%s_obj_%d", map_name, obj.id)

                -- Skip non-respawning items that were already picked up
                -- Items with respawn=true always spawn, items with respawn=false/nil only spawn if not picked
                if respawn or not picked_items[map_id] then
                    local center_x = obj.x + obj.width / 2
                    local center_y = obj.y + obj.height / 2

                    local item = self.world_item_class:new(center_x, center_y, item_type, quantity, map_id, respawn)

                    table.insert(self.world_items, item)
                end
            end
        end
    end
end

function loaders.loadParallax(self)
    -- Load parallax backgrounds from Tiled map
    local tiled_loader = require "engine.systems.parallax.tiled_loader"
    local parallax = require "engine.systems.parallax"

    -- Extract parallax layer configs from map
    local layer_configs = tiled_loader.loadParallaxLayers(self.map)

    -- Initialize parallax system if layers found
    if #layer_configs > 0 then
        parallax:init(layer_configs)
    else
        -- Clear parallax if no layers
        parallax:clear()
    end
end

-- Load stairs (topdown only)
-- Stairs create visual Y offset based on polygon shape
-- For diagonal stairs: player Y offset changes based on X position within polygon
function loaders.loadStairs(self)
    if self.game_mode ~= "topdown" then
        return
    end
    -- Find Stairs layer (STI stores layers by index, not name)
    local stairs_layer = nil
    for _, layer in ipairs(self.map.layers) do
        if layer.name == "Stairs" then
            stairs_layer = layer
            break
        end
    end

    if not stairs_layer then
        return
    end

    self.stairs = {}

    for i, obj in ipairs(stairs_layer.objects) do

        local stair = {
            x = obj.x,
            y = obj.y,
            width = obj.width,
            height = obj.height,
            shape = obj.shape or "rectangle",
        }

        -- Handle polygon shape
        if obj.polygon then
            stair.shape = "polygon"
            stair.polygon = {}
            -- NOTE: STI converts polygon vertices to world coordinates during map:init()
            -- See vendor/sti/init.lua lines 446-450: vertex.x = vertex.x + x
            -- So we use the vertices directly WITHOUT adding obj.x/obj.y
            for _, point in ipairs(obj.polygon) do
                table.insert(stair.polygon, {
                    x = point.x,
                    y = point.y
                })
            end

            -- Calculate bounding box for quick rejection test
            stair.bounds = geometry.polygonBounds(stair.polygon)

            -- Auto-detect stair direction from polygon shape
            -- Find the average Y at left edge vs right edge
            local b = stair.bounds
            local left_y_sum, left_count = 0, 0
            local right_y_sum, right_count = 0, 0
            local threshold = (b.max_x - b.min_x) * 0.3  -- 30% from each edge

            for _, p in ipairs(stair.polygon) do
                if p.x <= b.min_x + threshold then
                    left_y_sum = left_y_sum + p.y
                    left_count = left_count + 1
                elseif p.x >= b.max_x - threshold then
                    right_y_sum = right_y_sum + p.y
                    right_count = right_count + 1
                end
            end

            local mid_y = (b.min_y + b.max_y) / 2
            local avg_left_y = left_count > 0 and (left_y_sum / left_count) or mid_y
            local avg_right_y = right_count > 0 and (right_y_sum / right_count) or mid_y

            -- If left side is higher (lower Y), hill goes left
            -- If right side is higher (lower Y), hill goes right
            stair.hill_direction = avg_left_y < avg_right_y and "left" or "right"
        else
            -- Rectangle shape - use properties or default
            stair.hill_direction = obj.properties and obj.properties.hill_direction or "up"
        end

        table.insert(self.stairs, stair)
    end
end

-- Load props from Props layer
-- Groups tile objects by 'group' property
-- Collider object (type="collider") defines physics bounds
function loaders.loadProps(self, destroyed_props)
    if not self.prop_class then
        return
    end

    destroyed_props = destroyed_props or {}

    local props_layer = nil
    for _, layer in ipairs(self.map.layers) do
        if layer.name == "Props" then
            props_layer = layer
            break
        end
    end

    if not props_layer then
        return
    end

    -- Get map name for map_id generation
    local map_name = self.map.properties and self.map.properties.name or "unknown"

    -- Group objects by 'group' property
    local groups = {}
    local colliders = {}

    for _, obj in ipairs(props_layer.objects) do
        local group_name = obj.properties and obj.properties.group
        local obj_type = obj.properties and obj.properties.type

        if obj_type == "collider" then
            -- This is a collider definition
            if group_name then
                colliders[group_name] = obj
            end
        elseif obj.gid and group_name then
            -- This is a tile object with a group
            if not groups[group_name] then
                groups[group_name] = {}
            end
            table.insert(groups[group_name], obj)
        end
    end

    -- Create Props from groups
    for group_name, tiles in pairs(groups) do
        local collider_obj = colliders[group_name]
        if collider_obj then
            -- Generate map_id for this prop
            local map_id = map_name .. "_prop_" .. collider_obj.id

            -- Skip if destroyed (non-respawning)
            if not destroyed_props[map_id] then
                -- Create prop with tiles and collider
                local new_prop = self.prop_class:new(tiles, collider_obj, self.map)
                new_prop.world = self
                new_prop.map_id = map_id

                -- Create physics collider
                collision.createPropCollider(new_prop, self.physicsWorld, self.game_mode)

                table.insert(self.props, new_prop)
            end
        end
    end
end

-- Load vehicles from entity_registry (Single Source of Truth)
-- Vehicles are only loaded from Tiled ONCE on new game, then registry owns all state
function loaders.loadVehicles(self)
    if not self.vehicle_class then
        return
    end

    -- Skip if explicitly told not to load vehicles (e.g., during registry initialization)
    if self.skip_vehicle_loading then
        return
    end

    local entity_registry = require "engine.core.entity_registry"

    -- Get current map name
    local map_name = self.map.properties and self.map.properties.name or "unknown"

    -- Get all vehicles that are currently in this map (map-placed vehicles)
    local vehicles_for_map = entity_registry:getVehiclesForMap(map_name)

    for map_id, vehicle_data in pairs(vehicles_for_map) do
        -- Create vehicle entity from registry data
        local new_vehicle = self.vehicle_class:new(
            vehicle_data.x,
            vehicle_data.y,
            vehicle_data.type,
            map_id
        )
        new_vehicle.direction = vehicle_data.direction or "down"
        new_vehicle.world = self

        -- Create colliders
        collision.createVehicleCollider(new_vehicle, self.physicsWorld, self.game_mode)

        table.insert(self.vehicles, new_vehicle)
    end

    -- Load summoned vehicle if it exists in this map (owned vehicles)
    local summoned = entity_registry:getSummonedVehicle()
    if summoned and summoned.map == map_name then
        local summoned_id = "summoned_" .. summoned.type
        local new_vehicle = self.vehicle_class:new(
            summoned.x,
            summoned.y,
            summoned.type,
            summoned_id
        )
        new_vehicle.direction = summoned.direction or "down"
        new_vehicle.world = self
        new_vehicle.is_summoned = true  -- Mark as summoned (owned) vehicle

        -- Create colliders
        collision.createVehicleCollider(new_vehicle, self.physicsWorld, self.game_mode)

        table.insert(self.vehicles, new_vehicle)
    end
end

return loaders

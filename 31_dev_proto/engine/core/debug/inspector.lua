-- Semantic world inspector used by the opt-in localhost debug bridge.
--
-- It exposes stable IDs and a deliberately small set of mutations. No arbitrary
-- field access or code execution is supported.

local inspector = {
    world = nil,
    object_ids = setmetatable({}, {__mode = "k"}),
    objects = {},
    counters = {},
}

local ENTITY_COLLECTIONS = {
    {"enemy", "enemies"},
    {"npc", "npcs"},
    {"item", "world_items"},
    {"prop", "props"},
    {"vehicle", "vehicles"},
    {"healing_point", "healing_points"},
    {"savepoint", "savepoints"},
}

local COLLIDER_FIELDS = {
    "collider",
    "foot_collider",
    "ground_collider",
}

local PROPERTY_WRITELIST = {
    active = "boolean",
    can_interact = "boolean",
    cooldown = "number",
    direction = "string",
    health = "number",
    hp = "number",
    max_health = "number",
    max_hp = "number",
    quantity = "number",
    state = "string",
}

local function currentScene()
    return require("engine.core.scene_control").current
end

local function safeCall(target, method, ...)
    if not target or type(target[method]) ~= "function" then
        return nil
    end
    local success, first, second, third, fourth =
        pcall(target[method], target, ...)
    if not success then return nil end
    return first, second, third, fourth
end

local function isColliderAlive(collider)
    if not collider or not collider.body then return false end
    local destroyed = safeCall(collider, "isDestroyed")
    return destroyed ~= true
end

local function colliderBounds(collider)
    if not isColliderAlive(collider) then return nil end

    local min_x, min_y = math.huge, math.huge
    local max_x, max_y = -math.huge, -math.huge
    local found = false

    for _, fixture in pairs(collider.fixtures or {}) do
        local success, x1, y1, x2, y2 =
            pcall(fixture.getBoundingBox, fixture)
        if success and x1 and y1 and x2 and y2 then
            min_x = math.min(min_x, x1)
            min_y = math.min(min_y, y1)
            max_x = math.max(max_x, x2)
            max_y = math.max(max_y, y2)
            found = true
        end
    end

    if not found then return nil end
    return {
        x = min_x,
        y = min_y,
        width = max_x - min_x,
        height = max_y - min_y,
    }
end

local function pointToScreen(scene, x, y)
    if not x or not y then return nil end

    local screen_x, screen_y = x, y
    if scene and scene.cam and scene.cam.cameraCoords then
        local success, converted_x, converted_y =
            pcall(scene.cam.cameraCoords, scene.cam, x, y)
        if success then
            screen_x, screen_y = converted_x, converted_y
        end
    end

    local width, height = love.graphics.getDimensions()
    return {
        x = screen_x,
        y = screen_y,
        visible = screen_x >= 0 and screen_x <= width and
                  screen_y >= 0 and screen_y <= height,
    }
end

local function boundsToScreen(scene, bounds)
    if not bounds then return nil end
    local top_left = pointToScreen(scene, bounds.x, bounds.y)
    local bottom_right = pointToScreen(
        scene,
        bounds.x + bounds.width,
        bounds.y + bounds.height
    )
    if not top_left or not bottom_right then return nil end

    local x1 = math.min(top_left.x, bottom_right.x)
    local y1 = math.min(top_left.y, bottom_right.y)
    local x2 = math.max(top_left.x, bottom_right.x)
    local y2 = math.max(top_left.y, bottom_right.y)
    local width, height = love.graphics.getDimensions()
    return {
        x = x1,
        y = y1,
        width = x2 - x1,
        height = y2 - y1,
        visible = x2 >= 0 and y2 >= 0 and x1 <= width and y1 <= height,
    }
end

local function primaryCollider(object)
    if not object then return nil end
    for _, field in ipairs(COLLIDER_FIELDS) do
        if isColliderAlive(object[field]) then
            return object[field]
        end
    end
    if object.body and object.fixtures and isColliderAlive(object) then
        return object
    end
    return nil
end

local function objectPosition(object)
    if not object then return nil, nil end
    if type(object.x) == "number" and type(object.y) == "number" then
        return object.x, object.y
    end
    local collider = primaryCollider(object)
    return safeCall(collider, "getPosition")
end

function inspector:_resetForWorld(world)
    if self.world == world then return end
    self.world = world
    self.object_ids = setmetatable({}, {__mode = "k"})
    self.objects = {}
    self.counters = {}
end

function inspector:_register(kind, object, preferred_id)
    local existing = self.object_ids[object]
    if existing then
        self.objects[existing] = {kind = kind, object = object}
        return existing
    end

    local id = preferred_id
    if not id or self.objects[id] then
        local counter = (self.counters[kind] or 0) + 1
        self.counters[kind] = counter
        id = kind .. ":" .. counter
        while self.objects[id] do
            counter = counter + 1
            self.counters[kind] = counter
            id = kind .. ":" .. counter
        end
    end

    self.object_ids[object] = id
    self.objects[id] = {kind = kind, object = object}
    return id
end

function inspector:_entitySummary(scene, kind, object, preferred_id)
    local id = self:_register(kind, object, preferred_id)
    local x, y = objectPosition(object)
    local collider = primaryCollider(object)
    local bounds = colliderBounds(collider)
    if not bounds and x and y and object.width and object.height then
        bounds = {
            x = x,
            y = y,
            width = object.width,
            height = object.height,
        }
    elseif not bounds and x and y and object.radius then
        bounds = {
            x = x - object.radius,
            y = y - object.radius,
            width = object.radius * 2,
            height = object.radius * 2,
        }
    end
    local velocity_x, velocity_y = safeCall(collider, "getLinearVelocity")

    local result = {
        id = id,
        kind = kind,
        x = x,
        y = y,
        screen = pointToScreen(scene, x, y),
        bounds = bounds,
        screen_bounds = boundsToScreen(scene, bounds),
    }

    local fields = {
        "map_id", "type", "name", "state", "direction", "health",
        "max_health", "hp", "max_hp", "dead", "active", "can_interact",
        "is_boarded", "respawn", "quantity", "item_type", "cooldown",
        "cooldown_max", "breakable", "movable", "damage",
        "damage_cooldown", "interaction_range",
    }
    for _, field in ipairs(fields) do
        local value = object[field]
        local value_type = type(value)
        if value_type == "string" or value_type == "number" or
           value_type == "boolean" then
            result[field] = value
        end
    end

    if collider then
        result.collider = {
            id = collider.id,
            type = collider.type,
            collision_class = collider.collision_class,
            body_type = safeCall(collider, "getType"),
            velocity_x = velocity_x,
            velocity_y = velocity_y,
        }
    end
    return result
end

local function simpleArea(scene, area)
    if type(area) ~= "table" then return nil end
    local result = {}
    local fields = {
        "id", "name", "type", "x", "y", "width", "height", "target",
        "target_map", "spawn_x", "spawn_y", "damage", "intro_id",
        "transition_type", "allow_vehicle",
    }
    for _, field in ipairs(fields) do
        local value = area[field]
        if type(value) == "string" or type(value) == "number" or
           type(value) == "boolean" then
            result[field] = value
        end
    end
    if result.x and result.y then
        result.screen = pointToScreen(scene, result.x, result.y)
        if result.width and result.height then
            result.screen_bounds = boundsToScreen(scene, {
                x = result.x,
                y = result.y,
                width = result.width,
                height = result.height,
            })
        end
    end
    return result
end

function inspector:snapshot()
    local scene = currentScene()
    local world = scene and scene.world or nil
    self:_resetForWorld(world)

    if not world then
        return {
            available = false,
            reason = "Current scene has no world",
        }
    end

    local result = {
        available = true,
        game_mode = world.game_mode,
        map_path = scene.current_map_path,
        map = {},
        camera = scene.cam and {
            x = scene.cam.x,
            y = scene.cam.y,
            scale = scene.cam.scale,
            rotation = scene.cam.rot,
        } or nil,
        entities = {},
        walls = {},
        transitions = {},
        death_zones = {},
        damage_zones = {},
        counts = {},
    }

    local map = world.map
    if map then
        result.map = {
            name = map.properties and map.properties.name or nil,
            width_tiles = map.width,
            height_tiles = map.height,
            tile_width = map.tilewidth,
            tile_height = map.tileheight,
            width = map.width and map.tilewidth and map.width * map.tilewidth or nil,
            height = map.height and map.tileheight and map.height * map.tileheight or nil,
        }
    end

    if scene.player then
        result.entities[#result.entities + 1] =
            self:_entitySummary(scene, "player", scene.player, "player")
    end

    for _, collection_info in ipairs(ENTITY_COLLECTIONS) do
        local kind, field = collection_info[1], collection_info[2]
        local collection = world[field] or {}
        result.counts[field] = #collection
        for _, object in ipairs(collection) do
            local preferred = object.map_id or object.id
            preferred = preferred and (kind .. ":" .. tostring(preferred)) or nil
            result.entities[#result.entities + 1] =
                self:_entitySummary(scene, kind, object, preferred)
        end
    end

    result.counts.walls = #(world.walls or {})
    for _, wall in ipairs(world.walls or {}) do
        result.walls[#result.walls + 1] =
            self:_entitySummary(scene, "wall", wall)
    end

    for _, transition in ipairs(world.transitions or {}) do
        result.transitions[#result.transitions + 1] =
            simpleArea(scene, transition)
    end
    for _, zone in ipairs(world.death_zones or {}) do
        result.death_zones[#result.death_zones + 1] =
            self:_entitySummary(scene, "death_zone", zone)
    end
    for _, zone in ipairs(world.damage_zones or {}) do
        if zone.collider then
            local summary = self:_entitySummary(
                scene,
                "damage_zone",
                zone,
                zone.id and ("damage_zone:" .. tostring(zone.id)) or nil
            )
            result.damage_zones[#result.damage_zones + 1] = summary
        else
            result.damage_zones[#result.damage_zones + 1] =
                simpleArea(scene, zone)
        end
    end

    result.counts.entities = #result.entities
    result.counts.transitions = #result.transitions
    result.counts.death_zones = #result.death_zones
    result.counts.damage_zones = #result.damage_zones
    return result
end

function inspector:get(entity_id)
    self:snapshot()
    local entry = self.objects[entity_id]
    if not entry then
        return nil, "Unknown entityId: " .. tostring(entity_id)
    end
    return self:_entitySummary(
        currentScene(),
        entry.kind,
        entry.object,
        entity_id
    )
end

local function moveCollider(collider, delta_x, delta_y, stop_velocity)
    if not isColliderAlive(collider) then return end
    local x, y = safeCall(collider, "getPosition")
    if x and y then
        safeCall(collider, "setPosition", x + delta_x, y + delta_y)
    end
    if stop_velocity then
        safeCall(collider, "setLinearVelocity", 0, 0)
    end
end

function inspector:setPosition(entity_id, x, y, stop_velocity)
    self:snapshot()
    local entry = self.objects[entity_id]
    if not entry then
        return nil, "Unknown entityId: " .. tostring(entity_id)
    end

    local object = entry.object
    local old_x, old_y = objectPosition(object)
    if not old_x or not old_y then
        return nil, "Entity has no controllable position"
    end

    local delta_x, delta_y = x - old_x, y - old_y
    if object.body and object.fixtures then
        moveCollider(object, delta_x, delta_y, stop_velocity)
    else
        for _, field in ipairs(COLLIDER_FIELDS) do
            moveCollider(object[field], delta_x, delta_y, stop_velocity)
        end
        object.x, object.y = x, y
        if type(object.center_x) == "number" then
            object.center_x = object.center_x + delta_x
        end
        if type(object.center_y) == "number" then
            object.center_y = object.center_y + delta_y
        end
    end

    return self:_entitySummary(
        currentScene(),
        entry.kind,
        object,
        entity_id
    )
end

function inspector:setHealth(entity_id, value)
    self:snapshot()
    local entry = self.objects[entity_id]
    if not entry then
        return nil, "Unknown entityId: " .. tostring(entity_id)
    end

    local object = entry.object
    local field = object.health ~= nil and "health" or
                  (object.hp ~= nil and "hp" or nil)
    if not field then
        return nil, "Entity has no health field"
    end
    local maximum = field == "health" and object.max_health or object.max_hp
    object[field] = maximum and math.max(0, math.min(value, maximum)) or value

    return self:_entitySummary(
        currentScene(),
        entry.kind,
        object,
        entity_id
    )
end

function inspector:setProperty(entity_id, property, value)
    self:snapshot()
    local entry = self.objects[entity_id]
    if not entry then
        return nil, "Unknown entityId: " .. tostring(entity_id)
    end

    local expected_type = PROPERTY_WRITELIST[property]
    if not expected_type then
        return nil, "Property is not writable: " .. tostring(property)
    end
    if type(value) ~= expected_type then
        return nil, string.format(
            "Property %s requires %s",
            property,
            expected_type
        )
    end
    if entry.object[property] == nil then
        return nil, "Entity has no property: " .. property
    end

    entry.object[property] = value
    return self:_entitySummary(
        currentScene(),
        entry.kind,
        entry.object,
        entity_id
    )
end

function inspector:worldToScreen(x, y)
    return pointToScreen(currentScene(), x, y)
end

function inspector:drawOverlay(options)
    if not options.enabled then return end

    local snapshot = self:snapshot()
    if not snapshot.available then return end

    love.graphics.push("all")
    love.graphics.setLineWidth(1)
    local font = love.graphics.getFont()

    local function drawSummary(summary, color, show_label)
        local bounds = summary.screen_bounds
        local point = summary.screen
        love.graphics.setColor(color)
        if bounds and bounds.visible then
            love.graphics.rectangle(
                "line",
                math.floor(bounds.x) + 0.5,
                math.floor(bounds.y) + 0.5,
                math.max(1, math.floor(bounds.width)),
                math.max(1, math.floor(bounds.height))
            )
        end
        if point and point.visible then
            love.graphics.line(point.x - 4, point.y, point.x + 4, point.y)
            love.graphics.line(point.x, point.y - 4, point.x, point.y + 4)
            if show_label then
                local label = summary.id
                local width = font:getWidth(label)
                love.graphics.setColor(0, 0, 0, 0.8)
                love.graphics.rectangle(
                    "fill",
                    point.x + 5,
                    point.y - 8,
                    width + 4,
                    font:getHeight() + 2
                )
                love.graphics.setColor(color)
                love.graphics.print(label, point.x + 7, point.y - 7)
            end
        end
    end

    if options.walls then
        for _, wall in ipairs(snapshot.walls) do
            drawSummary(wall, {1, 0.2, 1, 0.8}, false)
        end
    end

    if options.entities then
        for _, entity in ipairs(snapshot.entities) do
            local color = entity.kind == "player" and {0.2, 1, 0.3, 1} or
                          entity.kind == "enemy" and {1, 0.2, 0.2, 1} or
                          {0.2, 0.8, 1, 1}
            drawSummary(entity, color, options.labels)
        end
    end

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 8, 8, 310, 24)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format(
        "DEV PROTO | entities %d | walls %d",
        snapshot.counts.entities or 0,
        snapshot.counts.walls or 0
    ), 14, 13)
    love.graphics.pop()
end

return inspector

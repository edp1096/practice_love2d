-- engine/systems/collision/zones.lua
-- Death zone and damage zone collider creation

local zones = {}

-- Create collider for death zone (returns collider or nil)
function zones.createDeathZone(obj, physicsWorld)
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
function zones.createDamageZone(obj, physicsWorld)
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

return zones

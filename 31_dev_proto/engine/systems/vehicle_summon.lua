-- engine/systems/vehicle_summon.lua
-- Vehicle summoning system for owned vehicles
-- Allows players to summon/dismiss owned vehicles at their current location

local entity_registry = require "engine.core.entity_registry"
local collision = require "engine.systems.collision"
local vehicle_sound = require "engine.entities.vehicle.sound"

local vehicle_summon = {
    -- Settings (injected from game config)
    settings = nil,

    -- Vehicle class (injected from game)
    vehicle_class = nil,

    -- Cooldown timer
    cooldown = 0,
}

-- Initialize with game settings
function vehicle_summon:init(settings, vehicle_class)
    self.settings = settings or {
        allow_summon = true,
        summon_cooldown = 3,
        one_summon_only = true,
        auto_dismiss_on_indoor = false,
        summon_cost = 0,
    }
    self.vehicle_class = vehicle_class
    self.cooldown = 0
end

-- Update cooldown timer
function vehicle_summon:update(dt)
    if self.cooldown > 0 then
        self.cooldown = self.cooldown - dt
    end
end

-- Check if summoning is allowed
function vehicle_summon:canSummon()
    if not self.settings or not self.settings.allow_summon then
        return false, "summon_disabled"
    end

    if self.cooldown > 0 then
        return false, "cooldown"
    end

    local owned = entity_registry:getOwnedVehicles()
    if #owned == 0 then
        return false, "no_vehicles"
    end

    return true, nil
end

-- Get list of owned vehicles that can be summoned
function vehicle_summon:getAvailableVehicles()
    return entity_registry:getOwnedVehicles()
end

-- Check if a specific vehicle is currently summoned
function vehicle_summon:isSummoned(vehicle_type)
    local summoned = entity_registry:getSummonedVehicle()
    return summoned and summoned.type == vehicle_type
end

-- Summon a vehicle at player's position
-- Returns: vehicle instance or nil, error message
function vehicle_summon:summon(vehicle_type, world, player)
    -- Check if summoning is allowed
    local can, reason = self:canSummon()
    if not can then
        return nil, reason
    end

    -- Check if player owns this vehicle type
    if not entity_registry:hasVehicle(vehicle_type) then
        return nil, "not_owned"
    end

    -- Check one_summon_only setting
    if self.settings.one_summon_only and entity_registry:hasSummonedVehicle() then
        -- Dismiss current summoned vehicle first
        self:dismiss(world)
    end

    -- Check summon cost
    if self.settings.summon_cost > 0 then
        local level_system = require "engine.core.level"
        if level_system:getGold() < self.settings.summon_cost then
            return nil, "not_enough_gold"
        end
        level_system:addGold(-self.settings.summon_cost)
    end

    -- Get map name
    local map_name = world.map.properties and world.map.properties.name or "unknown"

    -- Calculate spawn position (slightly offset from player)
    local spawn_x = player.x + 50
    local spawn_y = player.y

    -- Create vehicle instance
    local summoned_id = "summoned_" .. vehicle_type
    local new_vehicle = self.vehicle_class:new(
        spawn_x,
        spawn_y,
        vehicle_type,
        summoned_id
    )
    new_vehicle.direction = player.direction or "down"
    new_vehicle.world = world
    new_vehicle.is_summoned = true

    -- Create colliders
    collision.createVehicleCollider(new_vehicle, world.physicsWorld, world.game_mode)

    -- Add to world
    table.insert(world.vehicles, new_vehicle)

    -- Update registry
    entity_registry:setSummonedVehicle({
        type = vehicle_type,
        map = map_name,
        x = spawn_x,
        y = spawn_y,
        direction = new_vehicle.direction,
    })

    -- Play summon sound
    vehicle_sound.playSummon(new_vehicle)

    -- Start cooldown
    self.cooldown = self.settings.summon_cooldown or 3

    return new_vehicle, nil
end

-- Dismiss (remove) the currently summoned vehicle
function vehicle_summon:dismiss(world)
    local summoned = entity_registry:getSummonedVehicle()
    if not summoned then
        return false, "no_summoned"
    end

    -- Find and remove from world
    if world and world.vehicles then
        for i, vehicle in ipairs(world.vehicles) do
            if vehicle.is_summoned and vehicle.type == summoned.type then
                -- Disembark player if boarded
                if vehicle.is_boarded and vehicle.rider then
                    vehicle.rider:disembark()
                end

                -- Destroy colliders
                if vehicle.collider and not vehicle.collider:isDestroyed() then
                    vehicle.collider:destroy()
                end
                if vehicle.foot_collider and not vehicle.foot_collider:isDestroyed() then
                    vehicle.foot_collider:destroy()
                end
                if vehicle.ground_collider and not vehicle.ground_collider:isDestroyed() then
                    vehicle.ground_collider:destroy()
                end

                table.remove(world.vehicles, i)
                break
            end
        end
    end

    -- Clear registry
    entity_registry:clearSummonedVehicle()

    return true, nil
end

-- Get currently summoned vehicle info
function vehicle_summon:getSummoned()
    return entity_registry:getSummonedVehicle()
end

-- Check if any vehicle is currently summoned
function vehicle_summon:hasSummoned()
    return entity_registry:hasSummonedVehicle()
end

return vehicle_summon

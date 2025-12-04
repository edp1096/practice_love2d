-- engine/entities/vehicle/init.lua
-- Vehicle entity: rideable vehicles (horse, boat, etc.)
-- Similar to NPC but supports boarding/disembarking

local prompt = require "engine.systems.prompt"
local render = require "engine.entities.vehicle.render"
local text_ui = require "engine.utils.text"

local vehicle = {}
vehicle.__index = vehicle

-- Class-level type registry (injected from game)
vehicle.type_registry = {}

-- Vertical offset when boarded (vehicle appears below player)
local VEHICLE_Y_OFFSET = 24

function vehicle:new(x, y, vehicle_type, map_id, config)
    local instance = setmetatable({}, vehicle)

    -- If no config provided, try loading from type registry
    if not config then
        vehicle_type = vehicle_type or "horse"
        config = self.type_registry[vehicle_type]

        if not config then
            error("Unknown vehicle type: " .. tostring(vehicle_type) .. " (type registry not initialized?)")
        end
    end

    -- Position
    instance.x = x or 100
    instance.y = y or 100
    instance.type = vehicle_type or "horse"
    instance.map_id = map_id or ("vehicle_" .. math.random(10000))

    -- Properties from config
    instance.name = config.name or "Vehicle"
    instance.ride_speed = config.ride_speed or 400
    instance.interaction_range = config.interaction_range or 60

    -- Color box rendering (prototype - no sprites)
    instance.color = config.color or {0.6, 0.4, 0.2, 1}
    instance.width = config.width or 64
    instance.height = config.height or 40

    -- Collider dimensions
    instance.collider_width = config.collider_width or instance.width
    instance.collider_height = config.collider_height or instance.height
    instance.collider_offset_x = config.collider_offset_x or 0
    instance.collider_offset_y = config.collider_offset_y or 0

    -- State
    instance.is_boarded = false
    instance.rider = nil
    instance.can_interact = false
    instance.direction = "down"  -- Current facing direction

    -- Colliders (set by collision system)
    instance.collider = nil
    instance.foot_collider = nil  -- Topdown only

    -- World reference (set by world)
    instance.world = nil

    return instance
end

function vehicle:update(dt, player_x, player_y)
    -- When boarded, follow rider position and direction (with Y offset)
    if self.is_boarded and self.rider then
        self.x = self.rider.x
        self.y = self.rider.y + VEHICLE_Y_OFFSET
        self.direction = self.rider.direction

        -- Update collider positions (colliders follow the offset position)
        if self.collider and not self.collider:isDestroyed() then
            self.collider:setPosition(self.x, self.y)
        end
        if self.foot_collider and not self.foot_collider:isDestroyed() then
            local foot_y = self.y + self.collider_height * 0.35
            self.foot_collider:setPosition(self.x, foot_y)
        end

        self.can_interact = false
        return
    end

    -- Check if player is in interaction range
    local dx = player_x - self.x
    local dy = player_y - self.y
    local distance = math.sqrt(dx * dx + dy * dy)

    self.can_interact = (distance < self.interaction_range)
end

function vehicle:boardPlayer(player)
    if self.is_boarded then return false end

    self.is_boarded = true
    self.rider = player
    self.can_interact = false

    -- Disable collisions while boarded (set to sensor)
    if self.collider and not self.collider:isDestroyed() then
        self.collider:setSensor(true)
    end
    if self.foot_collider and not self.foot_collider:isDestroyed() then
        self.foot_collider:setSensor(true)
    end

    return true
end

function vehicle:disembarkPlayer()
    if not self.is_boarded then return nil end

    local rider = self.rider
    self.is_boarded = false
    self.rider = nil

    -- Re-enable collisions after disembark (except in platformer where vehicle is always sensor)
    local is_platformer = self.world and self.world.game_mode == "platformer"
    if not is_platformer then
        if self.collider and not self.collider:isDestroyed() then
            self.collider:setSensor(false)
        end
        if self.foot_collider and not self.foot_collider:isDestroyed() then
            self.foot_collider:setSensor(false)
        end
    end

    return rider
end

function vehicle:getColliderCenter()
    if self.collider and not self.collider:isDestroyed() then
        return self.collider:getX(), self.collider:getY()
    end
    return self.x, self.y
end

function vehicle:getColliderBounds()
    local cx, cy = self:getColliderCenter()
    return {
        left = cx - self.collider_width / 2,
        top = cy - self.collider_height / 2,
        right = cx + self.collider_width / 2,
        bottom = cy + self.collider_height / 2,
        width = self.collider_width,
        height = self.collider_height,
    }
end

function vehicle:draw()
    -- Don't draw if boarded (will be drawn with player)
    if self.is_boarded then return end

    render.draw(self)

    -- Draw interaction indicator
    if self.can_interact then
        prompt:draw("interact", self.x, self.y, -40)
    end
end

function vehicle:drawBoardedBefore()
    -- Draw vehicle BEFORE player (player covers vehicle) - only for "up" direction
    if self.direction == "up" then
        render.draw(self)
    end
end

function vehicle:drawBoardedAfter()
    -- Draw vehicle AFTER player (vehicle covers player) - for down/left/right
    if self.direction ~= "up" then
        render.draw(self)
    end
end

function vehicle:drawDebug()
    -- Draw interaction range
    love.graphics.setColor(0.8, 0.6, 0.2, 0.3)
    love.graphics.circle("line", self.x, self.y, self.interaction_range)

    -- Draw main collider bounds
    local bounds = self:getColliderBounds()
    love.graphics.setColor(0.8, 0.6, 0.2, 1)
    love.graphics.rectangle("line", bounds.left, bounds.top, bounds.width, bounds.height)

    -- Draw foot collider if exists (topdown mode)
    if self.foot_collider and not self.foot_collider:isDestroyed() then
        local foot_height = bounds.height * 0.3
        local foot_top = bounds.top + bounds.height * 0.7
        love.graphics.setColor(0.6, 0.8, 0.2, 1)
        love.graphics.rectangle("line", bounds.left, foot_top, bounds.width, foot_height)
    end

    -- Draw info
    local status = self.type
    if self.is_boarded then status = status .. " [BOARDED]" end
    text_ui:draw(status, self.x - 30, self.y - 50, {0.8, 0.6, 0.2, 1})

    love.graphics.setColor(1, 1, 1, 1)
end

return vehicle

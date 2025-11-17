-- engine/healing_point.lua
-- Healing point entity that restores player health

local constants = require "engine.core.constants"
local text_ui = require "engine.utils.text"

local healing_point = {}
healing_point.__index = healing_point

function healing_point:new(x, y, heal_amount, radius)
    local instance = setmetatable({}, healing_point)

    instance.x = x
    instance.y = y
    instance.heal_amount = heal_amount or constants.HEALING_POINT.DEFAULT_HEAL_AMOUNT
    instance.radius = radius or constants.HEALING_POINT.DEFAULT_RADIUS
    instance.cooldown = 0
    instance.cooldown_max = constants.HEALING_POINT.DEFAULT_COOLDOWN
    instance.active = true

    -- Visual effects
    instance.pulse_timer = 0
    instance.pulse_speed = constants.HEALING_POINT.PULSE_SPEED
    instance.particles = {}

    -- Collision
    instance.collider = nil

    return instance
end

function healing_point:update(dt, player)
    self.pulse_timer = self.pulse_timer + dt * self.pulse_speed

    -- Update cooldown
    if self.cooldown > 0 then
        self.cooldown = self.cooldown - dt
        if self.cooldown <= 0 then
            self.active = true
        end
    end

    -- Check collision with player
    if self.active and player then
        local dx = player.x - self.x
        local dy = player.y - self.y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance < self.radius and player.health < player.max_health then
            self:healPlayer(player)
        end
    end

    -- Update particles
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        p.life = p.life - dt
        p.y = p.y - p.speed * dt
        p.alpha = p.life / p.max_life

        if p.life <= 0 then
            table.remove(self.particles, i)
        end
    end

    -- Spawn particles when active
    if self.active and love.math.random() < 0.3 then
        self:spawnParticle()
    end
end

function healing_point:healPlayer(player)
    local old_health = player.health
    player.health = math.min(player.max_health, player.health + self.heal_amount)

    local healed = player.health - old_health
    if healed > 0 then
        self.active = false
        self.cooldown = self.cooldown_max

        -- Play heal sound
        local sound = require("engine.core.sound")
        if sound.playEffect then
            sound:playEffect("heal")
        end

        -- Spawn burst of particles
        for i = 1, 10 do
            self:spawnParticle()
        end
    end
end

function healing_point:spawnParticle()
    local angle = love.math.random() * math.pi * 2
    local dist = love.math.random() * self.radius * 0.5

    local speed_range = constants.HEALING_POINT.PARTICLE_MAX_SPEED - constants.HEALING_POINT.PARTICLE_MIN_SPEED
    table.insert(self.particles, {
        x = self.x + math.cos(angle) * dist,
        y = self.y + math.sin(angle) * dist,
        speed = constants.HEALING_POINT.PARTICLE_MIN_SPEED + love.math.random() * speed_range,
        life = 1.0 + love.math.random() * 0.5,
        max_life = 1.5,
        alpha = 1.0
    })
end

function healing_point:draw()
    -- Draw base circle
    if self.active then
        -- Pulsing green circle
        local pulse = 0.7 + 0.3 * math.sin(self.pulse_timer)
        love.graphics.setColor(0.2, 0.8, 0.2, 0.3 * pulse)
        love.graphics.circle("fill", self.x, self.y, self.radius)

        love.graphics.setColor(0.3, 1.0, 0.3, 0.6 * pulse)
        love.graphics.circle("line", self.x, self.y, self.radius)

        -- Center glow
        love.graphics.setColor(0.5, 1.0, 0.5, 0.8)
        love.graphics.circle("fill", self.x, self.y, 8)
    else
        -- Cooldown display
        local cooldown_ratio = 1 - (self.cooldown / self.cooldown_max)

        love.graphics.setColor(0.3, 0.3, 0.3, 0.3)
        love.graphics.circle("fill", self.x, self.y, self.radius)

        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
        love.graphics.circle("line", self.x, self.y, self.radius)

        -- Cooldown arc
        if cooldown_ratio < 1 then
            love.graphics.setColor(0.2, 0.6, 0.2, 0.4)
            love.graphics.arc("fill", self.x, self.y, self.radius * 0.7, -math.pi / 2, -math.pi / 2 + cooldown_ratio * math.pi * 2)
        end

        -- Center dimmed
        love.graphics.setColor(0.3, 0.5, 0.3, 0.5)
        love.graphics.circle("fill", self.x, self.y, 8)
    end

    -- Draw particles
    for _, p in ipairs(self.particles) do
        love.graphics.setColor(0.5, 1.0, 0.5, p.alpha * 0.8)
        love.graphics.circle("fill", p.x, p.y, 3)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function healing_point:drawDebug()
    love.graphics.setColor(0, 1, 0, 0.3)
    love.graphics.circle("line", self.x, self.y, self.radius)

    love.graphics.setColor(1, 1, 1, 1)
    local text = string.format("Heal: %d", self.heal_amount)
    if not self.active then
        text = text .. string.format("\nCD: %.1f", self.cooldown)
    end
    text_ui:draw(text, self.x - 20, self.y - self.radius - 20, {1, 1, 1, 1})
    love.graphics.setColor(1, 1, 1, 1)
end

return healing_point

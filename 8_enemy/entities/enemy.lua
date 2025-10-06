-- entities/enemy.lua
local anim8 = require "vendor.anim8"
local debug = require "systems.debug"

local enemy = {}
enemy.__index = enemy

function enemy:new(x, y, enemy_type)
    local instance = setmetatable({}, enemy)

    instance.x = x or 100
    instance.y = y or 100
    instance.speed = 100
    instance.type = enemy_type or "basic"

    instance.state = "idle"
    instance.state_timer = 0

    instance.detection_range = 200
    instance.attack_range = 50
    instance.patrol_points = {}
    instance.current_patrol_index = 1

    -- Initialize target position
    instance.target_x = instance.x
    instance.target_y = instance.y

    instance.health = 100
    instance.max_health = 100
    instance.damage = 10
    instance.attack_cooldown = 1.0
    instance.attack_timer = 0

    instance.spriteSheet = love.graphics.newImage("assets/images/enemy-sheet.png")
    instance.grid = anim8.newGrid(16, 32, instance.spriteSheet:getWidth(), instance.spriteSheet:getHeight())

    instance.animations = {}
    instance.animations.idle = anim8.newAnimation(instance.grid("1-3", 1), 0.2)
    instance.animations.walk = anim8.newAnimation(instance.grid("4-7", 1), 0.12)
    instance.animations.attack = anim8.newAnimation(instance.grid("8-11", 1), 0.1)

    instance.anim = instance.animations.idle
    instance.direction = "down"

    instance.collider = nil
    instance.width = 40
    instance.height = 40

    return instance
end

function enemy:update(dt, player_x, player_y)
    self.anim:update(dt)

    if self.attack_timer > 0 then
        self.attack_timer = self.attack_timer - dt
    end

    if self.state_timer > 0 then
        self.state_timer = self.state_timer - dt
    end

    if self.state == "idle" then
        self:updateIdle(dt, player_x, player_y)
    elseif self.state == "patrol" then
        self:updatePatrol(dt, player_x, player_y)
    elseif self.state == "chase" then
        self:updateChase(dt, player_x, player_y)
    elseif self.state == "attack" then
        self:updateAttack(dt, player_x, player_y)
    elseif self.state == "hit" then
        self:updateHit(dt)
    elseif self.state == "dead" then
        return 0, 0
    end

    -- Calculate movement velocity with nil check
    local vx, vy = 0, 0
    if (self.state == "patrol" or self.state == "chase") and self.target_x and self.target_y then
        local dx = self.target_x - self.x
        local dy = self.target_y - self.y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > 5 then
            vx = (dx / distance) * self.speed
            vy = (dy / distance) * self.speed
        end
    end

    return vx, vy
end

function enemy:updateIdle(dt, player_x, player_y)
    self.anim = self.animations.idle

    local distance = self:getDistanceToPoint(player_x, player_y)
    if distance < self.detection_range then
        -- Check line of sight before chasing
        if self.world and self.world:checkLineOfSight(self.x, self.y, player_x, player_y) then
            self:setState("chase")
        end
    end

    if self.state_timer <= 0 then
        if #self.patrol_points > 0 then
            self:setState("patrol")
        else
            self.state_timer = math.random(2, 5)
        end
    end
end

function enemy:updatePatrol(dt, player_x, player_y)
    self.anim = self.animations.walk

    local distance = self:getDistanceToPoint(player_x, player_y)
    if distance < self.detection_range then
        -- Check line of sight before chasing
        if self.world and self.world:checkLineOfSight(self.x, self.y, player_x, player_y) then
            self:setState("chase")
            return
        end
    end

    if #self.patrol_points > 0 then
        local patrol_point = self.patrol_points[self.current_patrol_index]
        self.target_x = patrol_point.x
        self.target_y = patrol_point.y

        local dist_to_point = self:getDistanceToPoint(self.target_x, self.target_y)
        if dist_to_point < 10 then
            self.current_patrol_index = self.current_patrol_index + 1
            if self.current_patrol_index > #self.patrol_points then
                self.current_patrol_index = 1
            end
            self:setState("idle")
        end
    end
end

function enemy:updateChase(dt, player_x, player_y)
    self.anim = self.animations.walk

    local distance = self:getDistanceToPoint(player_x, player_y)

    if distance < self.attack_range then
        self:setState("attack")
        return
    end

    if distance > self.detection_range * 1.5 then
        self:setState("idle")
        return
    end

    -- Lose sight if blocked by wall
    if self.world and not self.world:checkLineOfSight(self.x, self.y, player_x, player_y) then
        self:setState("idle")
        return
    end

    self.target_x = player_x
    self.target_y = player_y
end

function enemy:updateAttack(dt, player_x, player_y)
    self.anim = self.animations.attack

    if self.attack_timer <= 0 then
        self.attack_timer = self.attack_cooldown
    end

    if self.state_timer <= 0 then
        self:setState("chase")
    end
end

function enemy:updateHit(dt)
    if self.state_timer <= 0 then
        if self.health > 0 then
            self:setState("chase")
        else
            self:setState("dead")
        end
    end
end

function enemy:setState(new_state)
    self.state = new_state

    if new_state == "idle" then
        self.state_timer = math.random(1, 3)
    elseif new_state == "attack" then
        self.state_timer = 0.5
    elseif new_state == "hit" then
        self.state_timer = 0.3
    end
end

function enemy:takeDamage(damage)
    self.health = self.health - damage

    if self.health <= 0 then
        self.health = 0
        self:setState("dead")
    else
        self:setState("hit")
    end
end

function enemy:getDistanceToPoint(x, y)
    local dx = x - self.x
    local dy = y - self.y
    return math.sqrt(dx * dx + dy * dy)
end

function enemy:setPatrolPoints(points)
    self.patrol_points = points
end

function enemy:draw()
    -- Debug: Draw detection range
    if debug.debug_mode then
        -- Detection range (yellow circle)
        love.graphics.setColor(1, 1, 0, 0.1)
        love.graphics.circle("fill", self.x, self.y, self.detection_range)
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.circle("line", self.x, self.y, self.detection_range)

        -- Attack range (red circle)
        love.graphics.setColor(1, 0, 0, 0.1)
        love.graphics.circle("fill", self.x, self.y, self.attack_range)
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.circle("line", self.x, self.y, self.attack_range)
    end

    local scale = 4

    if self.state == "hit" then
        love.graphics.setColor(1, 1, 1, 1)
    elseif self.state == "dead" then
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end

    self.anim:draw(self.spriteSheet, self.x, self.y, nil, scale, scale, 8, 16)

    love.graphics.setColor(1, 1, 1, 1)

    -- Debug: Hitbox
    if debug.show_colliders and self.collider then
        love.graphics.setColor(1, 0, 0, 0.3)
        love.graphics.rectangle("fill", self.x - self.width / 2, self.y - self.height / 2, self.width, self.height)
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Health bar
    if self.health < self.max_health and self.state ~= "dead" then
        local bar_width = 40
        local bar_height = 4
        local health_percent = self.health / self.max_health

        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", self.x - bar_width / 2, self.y - 30, bar_width, bar_height)

        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", self.x - bar_width / 2, self.y - 30, bar_width * health_percent, bar_height)

        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Debug: State text
    if debug.debug_mode then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(self.state, self.x - 15, self.y + 30)

        -- Target position
        if self.target_x and self.target_y then
            love.graphics.setColor(0, 1, 0, 0.5)
            love.graphics.circle("fill", self.target_x, self.target_y, 5)
            love.graphics.line(self.x, self.y, self.target_x, self.target_y)
        end

        love.graphics.setColor(1, 1, 1, 1)

        -- Debug: Line of sight
        if self.state == "chase" then
            if self.world and self.world:checkLineOfSight(self.x, self.y, self.target_x, self.target_y) then
                love.graphics.setColor(0, 1, 0, 0.5) -- Green = can see
            else
                love.graphics.setColor(1, 0, 0, 0.5) -- Red = blocked
            end
            love.graphics.setLineWidth(2)
            love.graphics.line(self.x, self.y, self.target_x, self.target_y)
            love.graphics.setLineWidth(1)
        end
    end
end

return enemy

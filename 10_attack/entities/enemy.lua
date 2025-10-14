-- entities/enemy.lua
local anim8 = require "vendor.anim8"
local debug = require "systems.debug"

local enemy = {}
enemy.__index = enemy

-- Color swap shader
local color_swap_shader = nil

-- Enemy type configurations
local ENEMY_TYPES = {
    red_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 100,
        damage = 10,
        speed = 100,
        attack_cooldown = 1.0,
        detection_range = 200,
        attack_range = 50,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = nil,
        target_color = nil
    },
    green_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 80,
        damage = 8,
        speed = 120,
        attack_cooldown = 0.8,
        detection_range = 180,
        attack_range = 50,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 32,
        collider_offset_x = 0,
        collider_offset_y = 0,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 1.0, 0.0 }
    },
    blue_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 120,
        damage = 12,
        speed = 80,
        attack_cooldown = 1.2,
        detection_range = 220,
        attack_range = 50,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 20,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.0, 0.5, 1.0 }
    },
    purple_slime = {
        sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
        health = 150,
        damage = 15,
        speed = 90,
        attack_cooldown = 1.5,
        detection_range = 250,
        attack_range = 60,

        sprite_width = 16,
        sprite_height = 32,
        sprite_scale = 4,

        collider_width = 32,
        collider_height = 20,
        collider_offset_x = 0,
        collider_offset_y = 10,

        sprite_draw_offset_x = -32,
        sprite_draw_offset_y = -96,

        sprite_origin_x = 0,
        sprite_origin_y = 0,

        source_color = { 1.0, 0.0, 0.0 },
        target_color = { 0.8, 0.0, 1.0 }
    }
}

function enemy:new(x, y, enemy_type)
    local instance = setmetatable({}, enemy)

    -- Load shader on first use
    if not color_swap_shader then
        local shader_code = [[
            extern vec3 target_color;

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
            {
                vec4 pixel = Texel(texture, texture_coords);

                if (pixel.a > 0.0 && pixel.r > 0.1) {
                    if (pixel.r > pixel.g * 1.5 && pixel.r > pixel.b * 1.5) {
                        float original_brightness = max(max(pixel.r, pixel.g), pixel.b);
                        pixel.rgb = target_color * (original_brightness * 0.8);
                    }
                }

                return pixel * color;
            }
        ]]
        color_swap_shader = love.graphics.newShader(shader_code)
    end

    enemy_type = enemy_type or "red_slime"
    local config = ENEMY_TYPES[enemy_type]

    if not config then
        error("Unknown enemy type: " .. tostring(enemy_type))
    end

    instance.x = x or 100
    instance.y = y or 100
    instance.type = enemy_type

    print("Creating enemy: " .. enemy_type .. " at (" .. x .. ", " .. y .. ")")
    if config.target_color then
        print("  - Color swap enabled: RGB(" .. config.target_color[1] .. ", " .. config.target_color[2] .. ", " .. config.target_color[3] .. ")")
    end

    instance.speed = config.speed
    instance.health = config.health
    instance.max_health = config.health
    instance.damage = config.damage
    instance.attack_cooldown = config.attack_cooldown
    instance.detection_range = config.detection_range
    instance.attack_range = config.attack_range

    instance.source_color = config.source_color
    instance.target_color = config.target_color

    instance.collider_width = config.collider_width or 40
    instance.collider_height = config.collider_height or 40
    instance.collider_offset_x = config.collider_offset_x or 0
    instance.collider_offset_y = config.collider_offset_y or 0

    instance.sprite_width = config.sprite_width or 16
    instance.sprite_height = config.sprite_height or 32
    instance.sprite_scale = config.sprite_scale or 4
    instance.sprite_draw_offset_x = config.sprite_draw_offset_x or (-(instance.sprite_width * instance.sprite_scale / 2))
    instance.sprite_draw_offset_y = config.sprite_draw_offset_y or (-(instance.sprite_height * instance.sprite_scale))
    instance.sprite_origin_x = config.sprite_origin_x or 0
    instance.sprite_origin_y = config.sprite_origin_y or 0

    instance.state = "idle"
    instance.state_timer = 0

    instance.patrol_points = {}
    instance.current_patrol_index = 1

    instance.target_x = instance.x
    instance.target_y = instance.y

    instance.attack_timer = 0
    instance.has_attacked = false

    instance.hit_flash_timer = 0
    instance.hit_shake_x = 0
    instance.hit_shake_y = 0
    instance.hit_shake_intensity = 4

    -- Stun system (from parry)
    instance.stunned = false
    instance.stun_timer = 0

    instance.spriteSheet = love.graphics.newImage(config.sprite_sheet)
    instance.grid = anim8.newGrid(
        instance.sprite_width,
        instance.sprite_height,
        instance.spriteSheet:getWidth(),
        instance.spriteSheet:getHeight()
    )

    instance.animations = {}
    instance.animations.idle_right = anim8.newAnimation(instance.grid("1-3", 1), 0.2)
    instance.animations.walk_right = anim8.newAnimation(instance.grid("4-7", 1), 0.12)
    instance.animations.attack_right = anim8.newAnimation(instance.grid("8-11", 1), 0.1)

    instance.animations.idle_left = anim8.newAnimation(instance.grid("1-3", 2), 0.2)
    instance.animations.walk_left = anim8.newAnimation(instance.grid("4-7", 2), 0.12)
    instance.animations.attack_left = anim8.newAnimation(instance.grid("8-11", 2), 0.1)

    instance.anim = instance.animations.idle_right
    instance.direction = "right"

    instance.collider = nil

    instance.width = instance.collider_width
    instance.height = instance.collider_height

    return instance
end

function enemy:getColliderBounds()
    return {
        x = self.x + self.collider_offset_x,
        y = self.y + self.collider_offset_y,
        width = self.collider_width,
        height = self.collider_height
    }
end

function enemy:update(dt, player_x, player_y)
    self.anim:update(dt)

    if self.attack_timer > 0 then
        self.attack_timer = self.attack_timer - dt
    end

    if self.state_timer > 0 then
        self.state_timer = self.state_timer - dt
    end

    if self.hit_flash_timer > 0 then
        self.hit_flash_timer = self.hit_flash_timer - dt
    end

    -- Update stun timer
    if self.stunned then
        self.stun_timer = self.stun_timer - dt
        if self.stun_timer <= 0 then
            self.stunned = false
            self:setState("idle")
        end
    end

    if self.state == "hit" then
        self.hit_shake_x = (math.random() - 0.5) * 2 * self.hit_shake_intensity
        self.hit_shake_y = (math.random() - 0.5) * 2 * self.hit_shake_intensity
    else
        self.hit_shake_x = 0
        self.hit_shake_y = 0
    end

    -- If stunned, skip all AI updates
    if self.stunned then
        return 0, 0
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

    local vx, vy = 0, 0
    if (self.state == "patrol" or self.state == "chase") and self.target_x and self.target_y then
        local dx = self.target_x - self.x
        local dy = self.target_y - self.y
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > 5 then
            vx = (dx / distance) * self.speed
            vy = (dy / distance) * self.speed

            if math.abs(dx) > 5 then
                if dx > 0 then
                    self.direction = "right"
                else
                    self.direction = "left"
                end
            end
        end
    end

    return vx, vy
end

function enemy:updateIdle(dt, player_x, player_y)
    self.anim = self.animations["idle_" .. self.direction]

    local distance = self:getDistanceToPoint(player_x, player_y)
    if distance < self.detection_range then
        local collider_center_x = self.x + self.collider_offset_x
        local collider_center_y = self.y + self.collider_offset_y
        if self.world and self.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
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
    self.anim = self.animations["walk_" .. self.direction]

    local distance = self:getDistanceToPoint(player_x, player_y)
    if distance < self.detection_range then
        local collider_center_x = self.x + self.collider_offset_x
        local collider_center_y = self.y + self.collider_offset_y
        if self.world and self.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
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
    self.anim = self.animations["walk_" .. self.direction]

    local distance = self:getDistanceToPoint(player_x, player_y)

    if distance < self.attack_range then
        self:setState("attack")
        return
    end

    if distance > self.detection_range * 1.5 then
        self:setState("idle")
        return
    end

    local collider_center_x = self.x + self.collider_offset_x
    local collider_center_y = self.y + self.collider_offset_y
    if self.world and not self.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
        self:setState("idle")
        return
    end

    self.target_x = player_x
    self.target_y = player_y
end

function enemy:updateAttack(dt, player_x, player_y)
    self.anim = self.animations["attack_" .. self.direction]

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
        self.has_attacked = false
    elseif new_state == "hit" then
        self.state_timer = 0.3
        self.hit_flash_timer = 0.15
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

function enemy:stun(duration, is_perfect)
    self.stunned = true
    self.stun_timer = duration or (is_perfect and 2.5 or 1.5)
    self.state = "stunned"

    -- Visual feedback
    self.hit_flash_timer = 0.3
end

function enemy:getDistanceToPoint(x, y)
    local collider_center_x = self.x + self.collider_offset_x
    local collider_center_y = self.y + self.collider_offset_y
    local dx = x - collider_center_x
    local dy = y - collider_center_y
    return math.sqrt(dx * dx + dy * dy)
end

function enemy:setPatrolPoints(points)
    self.patrol_points = points
end

function enemy:draw()
    local collider_center_x = self.x + self.collider_offset_x
    local collider_center_y = self.y + self.collider_offset_y

    if debug.debug_mode then
        love.graphics.setColor(1, 1, 0, 0.1)
        love.graphics.circle("fill", collider_center_x, collider_center_y, self.detection_range)
        love.graphics.setColor(1, 1, 0, 0.5)
        love.graphics.circle("line", collider_center_x, collider_center_y, self.detection_range)

        love.graphics.setColor(1, 0, 0, 0.1)
        love.graphics.circle("fill", collider_center_x, collider_center_y, self.attack_range)
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.circle("line", collider_center_x, collider_center_y, self.attack_range)
    end

    local sprite_draw_x = collider_center_x + self.sprite_draw_offset_x + self.hit_shake_x
    local sprite_draw_y = collider_center_y + self.sprite_draw_offset_y + self.hit_shake_y

    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", collider_center_x, collider_center_y + 30, 18, 8)
    love.graphics.setColor(1, 1, 1, 1)

    if self.target_color then
        love.graphics.setShader(color_swap_shader)
        if color_swap_shader then
            color_swap_shader:send("target_color", self.target_color)
        end
    end

    local draw_color = { 1, 1, 1, 1 }

    if self.state == "hit" then
        draw_color = { 1, 1, 1, 1 }
    elseif self.state == "dead" then
        draw_color = { 0.5, 0.5, 0.5, 0.5 }
    elseif self.stunned then
        -- Stunned visual effect: pulsing yellow
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 8)
        draw_color = { 1, 1, pulse, 1 }
    end

    love.graphics.setColor(draw_color)

    self.anim:draw(
        self.spriteSheet,
        sprite_draw_x,
        sprite_draw_y,
        nil,
        self.sprite_scale,
        self.sprite_scale,
        self.sprite_origin_x,
        self.sprite_origin_y
    )

    if self.state == "hit" and self.hit_flash_timer > 0 then
        local flash_intensity = self.hit_flash_timer / 0.15
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 1, 1, flash_intensity * 0.7)
        self.anim:draw(
            self.spriteSheet,
            sprite_draw_x,
            sprite_draw_y,
            nil,
            self.sprite_scale,
            self.sprite_scale,
            self.sprite_origin_x,
            self.sprite_origin_y
        )
        love.graphics.setBlendMode("alpha")
    end

    -- Stun stars effect
    if self.stunned then
        local star_offset = 40
        local star_size = 8
        local time = love.timer.getTime()

        for i = 1, 3 do
            local angle = (time * 3 + i * (math.pi * 2 / 3))
            local star_x = collider_center_x + math.cos(angle) * star_offset
            local star_y = collider_center_y - 50 + math.sin(angle) * 15

            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.circle("fill", star_x, star_y, star_size)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.circle("line", star_x, star_y, star_size)
        end
    end

    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)

    if debug.show_colliders and self.collider then
        love.graphics.setColor(1, 0, 0, 0.3)
        local bounds = self:getColliderBounds()
        love.graphics.rectangle("fill", bounds.x - bounds.width / 2, bounds.y - bounds.height / 2, bounds.width, bounds.height)
        love.graphics.setColor(1, 1, 1, 1)
    end

    if self.health < self.max_health and self.state ~= "dead" then
        local bar_width = 40
        local bar_height = 4
        local health_percent = self.health / self.max_health

        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", collider_center_x - bar_width / 2, collider_center_y - 30, bar_width, bar_height)

        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.rectangle("fill", collider_center_x - bar_width / 2, collider_center_y - 30, bar_width * health_percent, bar_height)

        love.graphics.setColor(1, 1, 1, 1)
    end

    if debug.debug_mode then
        love.graphics.setColor(1, 1, 1, 1)
        local status = self.type .. " " .. self.state .. " (" .. self.direction .. ")"
        if self.stunned then
            status = status .. " STUNNED"
        end
        love.graphics.print(status, collider_center_x - 40, collider_center_y + 30)

        if self.target_x and self.target_y then
            love.graphics.setColor(0, 1, 0, 0.5)
            love.graphics.circle("fill", self.target_x, self.target_y, 5)
            love.graphics.line(collider_center_x, collider_center_y, self.target_x, self.target_y)
        end

        love.graphics.setColor(1, 1, 1, 1)

        if self.state == "chase" then
            if self.world and self.world:checkLineOfSight(collider_center_x, collider_center_y, self.target_x, self.target_y) then
                love.graphics.setColor(0, 1, 0, 0.5)
            else
                love.graphics.setColor(1, 0, 0, 0.5)
            end
            love.graphics.setLineWidth(2)
            love.graphics.line(collider_center_x, collider_center_y, self.target_x, self.target_y)
            love.graphics.setLineWidth(1)
        end
    end
end

return enemy

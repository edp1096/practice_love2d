-- entities/enemy/init.lua
-- Base enemy class: coordinates AI, rendering, and common properties

local anim8 = require "vendor.anim8"
local ai = require "entities.enemy.ai"
local render = require "entities.enemy.render"
local slime_types = require "entities.enemy.types.slime"

local enemy = {}
enemy.__index = enemy

function enemy:new(x, y, enemy_type)
    local instance = setmetatable({}, enemy)

    enemy_type = enemy_type or "red_slime"
    local config = slime_types.ENEMY_TYPES[enemy_type]

    if not config then
        error("Unknown enemy type: " .. tostring(enemy_type))
    end

    -- Position
    instance.x = x or 100
    instance.y = y or 100
    instance.type = enemy_type

    print("Creating enemy: " .. enemy_type .. " at (" .. x .. ", " .. y .. ")")
    if config.target_color then
        print("  - Color swap enabled: RGB(" .. config.target_color[1] .. ", " .. config.target_color[2] .. ", " .. config.target_color[3] .. ")")
    end

    -- Stats from config
    instance.speed = config.speed
    instance.health = config.health
    instance.max_health = config.health
    instance.damage = config.damage
    instance.attack_cooldown = config.attack_cooldown
    instance.detection_range = config.detection_range
    instance.attack_range = config.attack_range

    -- Color swap
    instance.source_color = config.source_color
    instance.target_color = config.target_color

    -- Collision properties
    instance.collider_width = config.collider_width or 40
    instance.collider_height = config.collider_height or 40
    instance.collider_offset_x = config.collider_offset_x or 0
    instance.collider_offset_y = config.collider_offset_y or 0

    -- Sprite properties
    instance.sprite_width = config.sprite_width or 16
    instance.sprite_height = config.sprite_height or 32
    instance.sprite_scale = config.sprite_scale or 4
    instance.sprite_draw_offset_x = config.sprite_draw_offset_x or (-(instance.sprite_width * instance.sprite_scale / 2))
    instance.sprite_draw_offset_y = config.sprite_draw_offset_y or (-(instance.sprite_height * instance.sprite_scale))
    instance.sprite_origin_x = config.sprite_origin_x or 0
    instance.sprite_origin_y = config.sprite_origin_y or 0

    -- AI state
    instance.state = "idle"
    instance.state_timer = 0

    -- Patrol
    instance.patrol_points = {}
    instance.current_patrol_index = 1
    instance.target_x = instance.x
    instance.target_y = instance.y

    -- Combat
    instance.attack_timer = 0
    instance.has_attacked = false

    -- Hit effects
    instance.hit_flash_timer = 0
    instance.hit_shake_x = 0
    instance.hit_shake_y = 0
    instance.hit_shake_intensity = 4

    -- Stun system
    instance.stunned = false
    instance.stun_timer = 0

    -- Animation
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

    -- Collider (set by world)
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

    -- Update timers
    if self.attack_timer > 0 then
        self.attack_timer = self.attack_timer - dt
    end

    if self.state_timer > 0 then
        self.state_timer = self.state_timer - dt
    end

    if self.hit_flash_timer > 0 then
        self.hit_flash_timer = self.hit_flash_timer - dt
    end

    -- Update stun
    if self.stunned then
        self.stun_timer = self.stun_timer - dt
        if self.stun_timer <= 0 then
            self.stunned = false
            ai.setState(self, "idle")
        end
    end

    -- Hit shake
    if self.state == "hit" then
        self.hit_shake_x = (math.random() - 0.5) * 2 * self.hit_shake_intensity
        self.hit_shake_y = (math.random() - 0.5) * 2 * self.hit_shake_intensity
    else
        self.hit_shake_x = 0
        self.hit_shake_y = 0
    end

    -- If stunned, skip AI
    if self.stunned then
        return 0, 0
    end

    -- Delegate to AI module
    return ai.update(self, dt, player_x, player_y)
end

function enemy:takeDamage(damage)
    self.health = self.health - damage

    if self.health <= 0 then
        self.health = 0
        ai.setState(self, "dead")
    else
        ai.setState(self, "hit")
    end
end

function enemy:stun(duration, is_perfect)
    self.stunned = true
    self.stun_timer = duration or (is_perfect and 1.5 or 0.5)
    self.state = "stunned"
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
    render.draw(self)
end

return enemy

-- entities/enemy/init.lua
-- Base enemy class: coordinates AI, rendering, common properties, and sound

local anim8 = require "vendor.anim8"
local ai = require "engine.entities.enemy.ai"
local render = require "engine.entities.enemy.render"
local enemy_sound = require "engine.entities.enemy.sound"
local weapon_class = require "engine.entities.weapon"
local constants = require "engine.core.constants"
local entity_base = require "engine.entities.base.entity"

local enemy = {}
enemy.__index = enemy

-- Inherit base entity methods
enemy.getColliderCenter = entity_base.getColliderCenter
enemy.getSpritePosition = entity_base.getSpritePosition
enemy.getColliderBounds = entity_base.getColliderBounds

-- Class-level type registry (injected from game)
enemy.type_registry = {}

-- Initialize enemy sounds (called once)
local sounds_initialized = false

-- Helper function to create animation from frames and rows
local function createAnimation(grid, frames, rows, duration)
    if type(frames) == "table" and type(rows) == "table" then
        -- Multiple frame ranges with multiple rows (e.g., walk_left)
        local all_frames = {}
        for i = 1, #frames do
            local frame_range = frames[i]
            local row = rows[i]
            for _, frame in ipairs(grid(frame_range, row)) do
                table.insert(all_frames, frame)
            end
        end
        return anim8.newAnimation(all_frames, duration)
    else
        -- Single frame range with single row
        return anim8.newAnimation(grid(frames, rows), duration)
    end
end

function enemy:new(x, y, enemy_type, config)
    local instance = setmetatable({}, enemy)

    -- Initialize sounds once
    if not sounds_initialized then
        enemy_sound.initialize()
        sounds_initialized = true
    end

    enemy_type = enemy_type or "red_slime"

    -- Use provided config, or fallback to type registry
    if not config then
        config = self.type_registry[enemy_type]
        if not config then
            error("Unknown enemy type: " .. tostring(enemy_type) .. " (type registry not initialized?)")
        end
    end

    -- Determine if this is a humanoid enemy (has animation frames)
    instance.is_humanoid = (config.idle_frames ~= nil)

    -- Position
    instance.x = x or 100
    instance.y = y or 100
    instance.type = enemy_type

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

    -- Initialize collision and sprite properties using base class
    entity_base.initializeCollider(instance, config)
    entity_base.initializeSprite(instance, config)

    -- AI state
    instance.state = constants.ENEMY_STATES.IDLE
    instance.state_timer = 0
    instance.previous_state = constants.ENEMY_STATES.IDLE

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
    instance.is_stunned = false
    instance.stun_timer = 0

    -- Sound
    instance.move_sound_timer = 0
    instance.move_sound_interval = 0.6

    -- Animation
    instance.spriteSheet = love.graphics.newImage(config.sprite_sheet)
    instance.grid = anim8.newGrid(
        instance.sprite_width,
        instance.sprite_height,
        instance.spriteSheet:getWidth(),
        instance.spriteSheet:getHeight()
    )

    instance.animations = {}

    if instance.is_humanoid then
        -- Humanoid has 4 directions (up, down, left, right) with slower animations
        local dirs = { "up", "down", "left", "right" }

        for _, dir in ipairs(dirs) do
            instance.animations["idle_" .. dir] = createAnimation(
                instance.grid,
                config.idle_frames[dir],
                config.idle_rows[dir],
                0.2 -- slower: 0.15 -> 0.2
            )

            instance.animations["walk_" .. dir] = createAnimation(
                instance.grid,
                config.walk_frames[dir],
                config.walk_rows[dir],
                0.15 -- slower: 0.1 -> 0.15
            )

            instance.animations["attack_" .. dir] = createAnimation(
                instance.grid,
                config.attack_frames[dir],
                config.attack_rows[dir],
                0.12 -- slower: 0.08 -> 0.12
            )
        end
    else
        -- Slime only has 2 directions (left, right)
        instance.animations.idle_right = anim8.newAnimation(instance.grid("1-3", 1), 0.2)
        instance.animations.walk_right = anim8.newAnimation(instance.grid("4-7", 1), 0.12)
        instance.animations.attack_right = anim8.newAnimation(instance.grid("8-11", 1), 0.1)

        instance.animations.idle_left = anim8.newAnimation(instance.grid("1-3", 2), 0.2)
        instance.animations.walk_left = anim8.newAnimation(instance.grid("4-7", 2), 0.12)
        instance.animations.attack_left = anim8.newAnimation(instance.grid("8-11", 2), 0.1)

        -- Create up/down as aliases to right for compatibility
        instance.animations.idle_up = instance.animations.idle_right
        instance.animations.idle_down = instance.animations.idle_right
        instance.animations.walk_up = instance.animations.walk_right
        instance.animations.walk_down = instance.animations.walk_right
        instance.animations.attack_up = instance.animations.attack_right
        instance.animations.attack_down = instance.animations.attack_right
    end

    instance.anim = instance.animations.idle_right
    instance.direction = "right"

    -- Weapon (only for humanoid enemies)
    if instance.is_humanoid then
        instance.weapon = weapon_class:new("axe")
        instance.weapon_drawn = true -- humanoids always have weapon drawn
    end

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
    if self.is_stunned then
        self.stun_timer = self.stun_timer - dt
        if self.stun_timer <= 0 then
            self.is_stunned = false
            ai.setState(self, "idle")
        end
    end

    -- Hit shake
    if self.state == constants.ENEMY_STATES.HIT then
        self.hit_shake_x = (math.random() - 0.5) * 2 * self.hit_shake_intensity
        self.hit_shake_y = (math.random() - 0.5) * 2 * self.hit_shake_intensity
    else
        self.hit_shake_x = 0
        self.hit_shake_y = 0
    end

    -- Movement sound
    if (self.state == "walk" or self.state == constants.ENEMY_STATES.CHASE) and not self.is_stunned and self.state ~= constants.ENEMY_STATES.DEAD then
        self.move_sound_timer = self.move_sound_timer + dt

        if self.move_sound_timer >= self.move_sound_interval then
            enemy_sound.playMove(self.type)
            self.move_sound_timer = 0
        end
    else
        self.move_sound_timer = 0
    end

    -- If stunned, skip AI
    if self.is_stunned then
        return 0, 0
    end

    -- Store previous state for sound detection
    self.previous_state = self.state

    -- Update weapon for humanoid enemies
    if self.is_humanoid and self.weapon then
        -- Map state to actual animation name
        local anim_base = self.state
        if self.state == constants.ENEMY_STATES.CHASE or self.state == constants.ENEMY_STATES.PATROL then
            anim_base = "walk"
        elseif self.state == constants.ENEMY_STATES.HIT or self.state == constants.ENEMY_STATES.DEAD or self.state == "stunned" then
            anim_base = "idle"
        end

        local anim_name = anim_base .. "_" .. self.direction
        local frame_index = math.floor(self.anim.position) + 1

        local sprite_x, sprite_y = self:getSpritePosition()

        self.weapon:update(dt, sprite_x, sprite_y, 0, self.direction, anim_name, frame_index, false)
    end

    -- Delegate to AI module
    return ai.update(self, dt, player_x, player_y)
end

function enemy:takeDamage(damage)
    self.health = self.health - damage

    if self.health <= 0 then
        self.health = 0
        ai.setState(self, "dead")

        -- Play death sound
        enemy_sound.playDeath(self.type)
    else
        ai.setState(self, "hit")

        -- Play hurt sound
        enemy_sound.playHurt(self.type)
    end
end

function enemy:stun(duration, is_perfect)
    self.is_stunned = true
    self.stun_timer = duration or (is_perfect and 1.5 or 0.5)
    self.state = "stunned"
    self.hit_flash_timer = 0.3

    -- Play stunned sound
    enemy_sound.playStunned(self.type)
end

function enemy:getDistanceToPoint(x, y)
    local collider_center_x, collider_center_y = self:getColliderCenter()
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

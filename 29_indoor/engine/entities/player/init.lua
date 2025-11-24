-- engine/entities/player/init.lua
-- Main player module that coordinates all subsystems

local combat = require "engine.entities.player.combat"
local render = require "engine.entities.player.render"
local animation = require "engine.entities.player.animation"
local constants = require "engine.core.constants"

local player = {}
player.__index = player

function player:new(x, y, config)
    local instance = setmetatable({}, player)

    -- Load config (default or provided)
    config = config or {}
    local stats = config.stats or {}
    local spawn = config.spawn or {}
    local sprite = config.sprite or {}
    local collider_cfg = config.collider or {}

    instance.x = x or spawn.x or constants.PLAYER.DEFAULT_X
    instance.y = y or spawn.y or constants.PLAYER.DEFAULT_Y
    instance.speed = stats.speed or constants.PLAYER.DEFAULT_SPEED

    -- Game mode (will be set by play scene)
    instance.game_mode = "topdown"

    -- Platformer specific variables
    instance.jump_power = stats.jump_power or constants.PLAYER.JUMP_POWER
    instance.is_jumping = false
    instance.is_grounded = true  -- Assume starting on ground
    instance.was_grounded = true  -- Previous frame grounded state
    instance.can_jump = true
    instance.last_input_x = 0  -- Store last horizontal input for jump

    -- Topdown jump variables (visual only, no physics collision)
    instance.topdown_jump_height = 0        -- Current height above ground (pixels)
    instance.topdown_jump_velocity = 0      -- Vertical velocity
    instance.topdown_is_jumping = false     -- Jump state
    instance.topdown_max_jump_height = stats.topdown_max_jump_height or 50
    instance.topdown_jump_strength = stats.topdown_jump_strength or 400

    -- Sprite configuration
    instance.sprite_width = sprite.width or 48
    instance.sprite_height = sprite.height or 48
    instance.sprite_scale = sprite.scale or 3
    instance.sprite_origin_x = instance.sprite_width / 2
    instance.sprite_origin_y = instance.sprite_height / 2

    assert(sprite.sheet, "Player sprite sheet must be provided in config")
    animation.initialize(instance, sprite.sheet, sprite.width or 48, sprite.height or 48)

    combat.initialize(instance, config.combat)

    -- Collider configuration
    instance.collider = nil
    instance.collider_width = collider_cfg.width or constants.PLAYER.DEFAULT_WIDTH
    instance.collider_height = collider_cfg.height or constants.PLAYER.DEFAULT_HEIGHT

    return instance
end

function player:update(dt, cam, dialogue_open)
    combat.updateTimers(self, dt)

    -- Update topdown jump physics (visual only)
    if self.game_mode == "topdown" and self.topdown_is_jumping then
        -- Apply gravity
        local gravity = 2400  -- Pixels per second squared (2x faster fall)
        self.topdown_jump_velocity = self.topdown_jump_velocity + gravity * dt

        -- Update height
        self.topdown_jump_height = self.topdown_jump_height + self.topdown_jump_velocity * dt

        -- Land on ground
        if self.topdown_jump_height >= 0 then
            self.topdown_jump_height = 0
            self.topdown_jump_velocity = 0
            self.topdown_is_jumping = false
        end
    end

    local vx, vy = animation.update(self, dt, cam, dialogue_open)

    return vx, vy
end

function player:attack() return combat.attack(self) end

function player:startParry() return combat.startParry(self) end

function player:startDodge() return combat.startDodge(self) end

function player:startEvade() return combat.startEvade(self) end

function player:jump()
    if self.game_mode == "platformer" then
        -- Platformer: Physics-based jump
        local grounded = self.is_grounded or self.was_grounded

        if self.can_jump and grounded and self.collider then
            local input_vx = (self.last_input_x or 0) * self.speed
            self.collider:setLinearVelocity(input_vx, -self.jump_power)
            self.is_jumping = true
            self.can_jump = false
            return true
        end
    elseif self.game_mode == "topdown" then
        -- Topdown: Visual jump (no physics)
        if not self.topdown_is_jumping then
            self.topdown_is_jumping = true
            self.topdown_jump_velocity = -self.topdown_jump_strength
            return true
        end
    end
    return false
end

function player:checkParry(damage) return combat.checkParry(self, damage) end

function player:takeDamage(damage, shake_callback) return combat.takeDamage(self, damage, shake_callback) end

function player:isAlive() return combat.isAlive(self) end

function player:isInvincible() return combat.isInvincible(self) end

function player:isParrying() return combat.isParrying(self) end

function player:isDodging() return combat.isDodging(self) end

function player:isDodgeInvincible() return combat.isDodgeInvincible(self) end

function player:isEvading() return combat.isEvading(self) end

function player:draw() render.draw(self) end

function player:drawWeapon() render.drawWeapon(self) end

function player:drawAll() render.drawAll(self) end

function player:drawDebug() render.drawDebug(self) end

-- Equipment system wrappers
function player:equipWeapon(weapon_type) return combat.equipWeapon(self, weapon_type) end

function player:unequipWeapon() return combat.unequipWeapon(self) end

function player:applyEquipmentStats(stats) return combat.applyEquipmentStats(self, stats) end

function player:removeEquipmentStats(stats) return combat.removeEquipmentStats(self, stats) end

return player

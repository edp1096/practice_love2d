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

    assert(sprite.sheet, "Player sprite sheet must be provided in config")
    animation.initialize(instance, sprite.sheet)

    combat.initialize(instance, config.combat)

    instance.collider = nil
    instance.width = constants.PLAYER.DEFAULT_WIDTH
    instance.height = constants.PLAYER.DEFAULT_HEIGHT

    return instance
end

function player:update(dt, cam, dialogue_open)
    combat.updateTimers(self, dt)

    local vx, vy = animation.update(self, dt, cam, dialogue_open)

    return vx, vy
end

function player:attack() return combat.attack(self) end

function player:startParry() return combat.startParry(self) end

function player:startDodge() return combat.startDodge(self) end

function player:jump()
    -- Allow jump if grounded in current OR previous frame (fixes timing issue)
    local grounded = self.is_grounded or self.was_grounded

    if self.game_mode == "platformer" and self.can_jump and grounded and self.collider then
        -- Use input direction instead of current velocity for horizontal component
        -- This allows jumping even when pushing against a wall
        local input_vx = (self.last_input_x or 0) * self.speed

        self.collider:setLinearVelocity(input_vx, -self.jump_power)
        self.is_jumping = true
        self.can_jump = false
        return true
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

function player:draw() render.draw(self) end

function player:drawWeapon() render.drawWeapon(self) end

function player:drawAll() render.drawAll(self) end

function player:drawDebug() render.drawDebug(self) end

return player

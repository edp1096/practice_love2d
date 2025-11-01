-- entities/player/init.lua
-- Main player module that coordinates all subsystems

local combat = require "entities.player.combat"
local render = require "entities.player.render"
local animation = require "entities.player.animation"

local player = {}
player.__index = player

function player:new(sprite_sheet, x, y)
    local instance = setmetatable({}, player)

    instance.x = x or 400
    instance.y = y or 200
    instance.speed = 300

    -- Game mode (will be set by play scene)
    instance.game_mode = "topdown"

    -- Platformer specific variables
    instance.jump_power = -600
    instance.is_jumping = false
    instance.is_grounded = true  -- Assume starting on ground
    instance.can_jump = true
    instance.last_input_x = 0  -- Store last horizontal input for jump

    animation.initialize(instance, sprite_sheet)

    combat.initialize(instance)

    instance.collider = nil
    instance.width = 50
    instance.height = 100

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
    print("DEBUG player:jump() called:")
    print("  game_mode = " .. tostring(self.game_mode))
    print("  can_jump = " .. tostring(self.can_jump))
    print("  is_grounded = " .. tostring(self.is_grounded))
    print("  collider = " .. tostring(self.collider))

    if self.game_mode == "platformer" and self.can_jump and self.is_grounded and self.collider then
        -- Use input direction instead of current velocity for horizontal component
        -- This allows jumping even when pushing against a wall
        local input_vx = (self.last_input_x or 0) * self.speed

        print("  Current input: last_input_x=" .. tostring(self.last_input_x))
        print("  Calculated vx=" .. input_vx)

        self.collider:setLinearVelocity(input_vx, self.jump_power)
        self.is_jumping = true
        self.can_jump = false
        print("  JUMP EXECUTED!")
        return true
    end
    print("  JUMP FAILED - conditions not met")
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

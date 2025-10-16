-- entities/player/init.lua
-- Main player module that coordinates all subsystems

local combat = require "entities.player.combat"
local render = require "entities.player.render"
local animation = require "entities.player.animation"

local player = {}
player.__index = player

function player:new(sprite_sheet, x, y)
    local instance = setmetatable({}, player)

    -- Position
    instance.x = x or 400
    instance.y = y or 200
    instance.speed = 300

    -- Load sprite and animations (delegate to animation module)
    animation.initialize(instance, sprite_sheet)

    -- Combat state (delegate to combat module)
    combat.initialize(instance)

    -- Collision properties
    instance.collider = nil
    instance.width = 50
    instance.height = 100

    return instance
end

function player:update(dt, cam)
    -- Update combat timers
    combat.updateTimers(self, dt)

    -- Update direction and animation
    local vx, vy = animation.update(self, dt, cam)

    return vx, vy
end

-- Delegate combat methods
function player:attack() return combat.attack(self) end

function player:startParry() return combat.startParry(self) end

function player:startDodge() return combat.startDodge(self) end

function player:checkParry(damage) return combat.checkParry(self, damage) end

function player:takeDamage(damage, shake_callback) return combat.takeDamage(self, damage, shake_callback) end

function player:isAlive() return combat.isAlive(self) end

function player:isInvincible() return combat.isInvincible(self) end

function player:isParrying() return combat.isParrying(self) end

function player:isDodging() return combat.isDodging(self) end

function player:isDodgeInvincible() return combat.isDodgeInvincible(self) end

-- Delegate rendering methods
function player:draw() render.draw(self) end

function player:drawWeapon() render.drawWeapon(self) end

function player:drawAll() render.drawAll(self) end

function player:drawDebug() render.drawDebug(self) end

return player

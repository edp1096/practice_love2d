-- entities/player.lua
-- Player entity: handles input, animation, and movement intent

local anim8 = require "vendor.anim8"
local debug = require "systems.debug"

local player = {}
player.__index = player

function player:new(sprite_sheet, x, y)
    local instance = setmetatable({}, player)

    -- Position
    instance.x = x or 400
    instance.y = y or 200
    instance.speed = 300

    -- Sprite and animation
    instance.spriteSheet = love.graphics.newImage(sprite_sheet)
    instance.grid = anim8.newGrid(12, 18, instance.spriteSheet:getWidth(), instance.spriteSheet:getHeight())

    instance.animations = {}
    instance.animations.up = anim8.newAnimation(instance.grid("1-4", 4), 0.12)
    instance.animations.down = anim8.newAnimation(instance.grid("1-4", 1), 0.12)
    instance.animations.left = anim8.newAnimation(instance.grid("1-4", 2), 0.12)
    instance.animations.right = anim8.newAnimation(instance.grid("1-4", 3), 0.12)

    instance.anim = instance.animations.left
    instance.direction = "left"

    -- Collision properties (will be set by World system)
    instance.collider = nil
    instance.width = 50
    instance.height = 100

    return instance
end

function player:update(dt)
    local is_moving = false
    local vx, vy = 0, 0

    -- Input handling
    if love.keyboard.isDown("right", "d") then
        vx = self.speed
        self.anim = self.animations.right
        self.direction = "right"
        is_moving = true
    end

    if love.keyboard.isDown("left", "a") then
        vx = -self.speed
        self.anim = self.animations.left
        self.direction = "left"
        is_moving = true
    end

    if love.keyboard.isDown("down", "s") then
        vy = self.speed
        self.anim = self.animations.down
        self.direction = "down"
        is_moving = true
    end

    if love.keyboard.isDown("up", "w") then
        vy = -self.speed
        self.anim = self.animations.up
        self.direction = "up"
        is_moving = true
    end

    if is_moving then
        self.anim:update(dt)   -- Update animation
    else
        self.anim:gotoFrame(2) -- Idle frame
    end

    return vx, vy
end

function player:draw()
    -- Draw player sprite at current position
    self.anim:draw(self.spriteSheet, self.x, self.y, nil, 6, nil, 6, 9)

    -- Debug hitbox
    if debug.show_colliders and self.collider then
        love.graphics.setColor(0, 1, 0, 0.3)
        love.graphics.rectangle("fill", self.x - self.width / 2, self.y - self.height / 2, self.width, self.height)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

return player

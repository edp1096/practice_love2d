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
    instance.grid = anim8.newGrid(48, 48, instance.spriteSheet:getWidth(), instance.spriteSheet:getHeight())

    instance.animations = {}

    -- Walk
    instance.animations.walk_up = anim8.newAnimation(instance.grid("1-4", 4), 0.1)
    instance.animations.walk_down = anim8.newAnimation(instance.grid("1-4", 3), 0.1)
    instance.animations.walk_left = anim8.newAnimation(instance.grid("5-8", 4, "1-2", 5), 0.1)
    instance.animations.walk_right = anim8.newAnimation(instance.grid("3-8", 5), 0.1)

    -- Idle (single frame or short loop)
    instance.animations.idle_up = anim8.newAnimation(instance.grid("5-8", 1), 0.15)
    instance.animations.idle_down = anim8.newAnimation(instance.grid("1-4", 1), 0.15)
    instance.animations.idle_left = anim8.newAnimation(instance.grid("1-4", 2), 0.15)
    instance.animations.idle_right = anim8.newAnimation(instance.grid("5-8", 2), 0.15)

    instance.anim = instance.animations.idle_right
    instance.direction = "right"

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
        self.anim = self.animations.walk_right
        self.direction = "right"
        is_moving = true
    end

    if love.keyboard.isDown("left", "a") then
        vx = -self.speed
        self.anim = self.animations.walk_left
        self.direction = "left"
        is_moving = true
    end

    if love.keyboard.isDown("down", "s") then
        vy = self.speed
        self.anim = self.animations.walk_down
        self.direction = "down"
        is_moving = true
    end

    if love.keyboard.isDown("up", "w") then
        vy = -self.speed
        self.anim = self.animations.walk_up
        self.direction = "up"
        is_moving = true
    end

    if is_moving then
        self.anim:update(dt) -- Update animation
    else
        -- Use idle animation for current direction
        self.anim = self.animations["idle_" .. self.direction]
        self.anim:update(dt) -- Update idle animation (for breathing effect, etc.)
    end

    return vx, vy
end

function player:draw()
    -- Draw player sprite at current position
    self.anim:draw(self.spriteSheet, self.x, self.y, nil, 3, nil, 24, 24)

    -- Debug hitbox
    if debug.show_colliders and self.collider then
        love.graphics.setColor(0, 1, 0, 0.3)
        love.graphics.rectangle("fill", self.x - self.width / 2, self.y - self.height / 2, self.width, self.height)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

return player

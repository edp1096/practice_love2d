local anim8 = require "vendor.anim8"

local player = {}

function player:New(sprite_sheet)
    self.x = 400
    self.y = 200
    self.speed = 5
    self.spriteSheet = love.graphics.newImage(sprite_sheet)

    self.grid = anim8.newGrid(12, 18, self.spriteSheet:getWidth(), self.spriteSheet:getHeight())
    self.animations = {}
    self.animations.up = anim8.newAnimation(self.grid("1-4", 4), 0.12)
    self.animations.down = anim8.newAnimation(self.grid("1-4", 1), 0.12)
    self.animations.left = anim8.newAnimation(self.grid("1-4", 2), 0.12)
    self.animations.right = anim8.newAnimation(self.grid("1-4", 3), 0.12)

    self.anim = self.animations.left
end

function player:Update(dt)
    local is_moving = false

    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then
        self.x = self.x + self.speed
        self.anim = self.animations.right
        is_moving = true
    end
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then
        self.x = self.x - self.speed
        self.anim = self.animations.left
        is_moving = true
    end
    if love.keyboard.isDown("down") or love.keyboard.isDown("s") then
        self.y = self.y + self.speed
        self.anim = self.animations.down
        is_moving = true
    end
    if love.keyboard.isDown("up") or love.keyboard.isDown("w") then
        self.y = self.y - self.speed
        self.anim = self.animations.up
        is_moving = true
    end

    if not is_moving then
        self.anim:gotoFrame(2)
    end

    self.anim:update(dt)
end

return player

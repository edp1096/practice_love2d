-- entities/player.lua
-- Player entity: handles input, animation, and movement intent

local anim8 = require "vendor.anim8"
local debug = require "systems.debug"
local weapon_class = require "entities.weapon"

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

    -- Attack
    instance.animations.attack_down = anim8.newAnimation(instance.grid("1-4", 11), 0.08)
    instance.animations.attack_up = anim8.newAnimation(instance.grid("5-8", 11), 0.08)
    instance.animations.attack_left = anim8.newAnimation(instance.grid("1-4", 12), 0.08)
    instance.animations.attack_right = anim8.newAnimation(instance.grid("5-8", 12), 0.08)

    instance.anim = instance.animations.idle_right
    instance.direction = "right"

    -- Collision properties (will be set by World system)
    instance.collider = nil
    instance.width = 50
    instance.height = 100

    -- Combat system
    instance.weapon = weapon_class:new("sword")
    instance.state = "idle" -- idle, walking, attacking
    instance.attack_cooldown = 0
    instance.attack_cooldown_max = 0.5

    -- Facing angle (for weapon direction)
    instance.facing_angle = 0

    return instance
end

function player:update(dt, cam)
    -- Update attack cooldown
    if self.attack_cooldown > 0 then
        self.attack_cooldown = self.attack_cooldown - dt
    end

    -- Calculate facing angle from mouse position
    -- Convert screen coordinates to world coordinates using camera
    local mouse_x, mouse_y
    if cam then
        mouse_x, mouse_y = cam:worldCoords(love.mouse.getPosition())
    else
        mouse_x, mouse_y = love.mouse.getPosition()
    end

    -- Calculate raw angle to mouse
    local raw_angle = math.atan2(mouse_y - self.y, mouse_x - self.x)

    -- Snap to 4 directions and update player direction
    if raw_angle > -math.pi / 4 and raw_angle <= math.pi / 4 then
        -- Right (east: -45° to 45°)
        self.direction = "right"
        -- self.facing_angle = 0
        self.facing_angle = 1.7
    elseif raw_angle > math.pi / 4 and raw_angle <= 3 * math.pi / 4 then
        -- Down (south: 45° to 135°)
        self.direction = "down"
        -- self.facing_angle = math.pi / 2
        self.facing_angle = math.pi / 2
    elseif raw_angle > 3 * math.pi / 4 or raw_angle <= -3 * math.pi / 4 then
        -- Left (west: 135° to -135°)
        self.direction = "left"
        self.facing_angle = math.pi
    else
        -- Up (north: -135° to -45°)
        self.direction = "up"
        self.facing_angle = -math.pi / 2
    end

    -- Update weapon
    self.weapon:update(dt, self.x, self.y, self.facing_angle)

    -- Check if attack animation finished
    if self.state == "attacking" and not self.weapon.is_attacking then
        self.state = "idle"
    end

    local is_moving = false
    local vx, vy = 0, 0

    -- Only allow movement if not attacking
    if self.state ~= "attacking" then
        -- Input handling (direction is now controlled by mouse, not WASD)
        if love.keyboard.isDown("right", "d") then
            vx = self.speed
            is_moving = true
        end

        if love.keyboard.isDown("left", "a") then
            vx = -self.speed
            is_moving = true
        end

        if love.keyboard.isDown("down", "s") then
            vy = self.speed
            is_moving = true
        end

        if love.keyboard.isDown("up", "w") then
            vy = -self.speed
            is_moving = true
        end

        if is_moving then
            -- Use walk animation for current direction (set by mouse)
            self.anim = self.animations["walk_" .. self.direction]
            self.anim:update(dt)
            self.state = "walking"
        else
            -- Use idle animation for current direction (set by mouse)
            self.anim = self.animations["idle_" .. self.direction]
            self.anim:update(dt)
            if self.state ~= "attacking" then
                self.state = "idle"
            end
        end
    else
        -- During attack, use proper attack animation
        self.anim = self.animations["attack_" .. self.direction]
        self.anim:update(dt)
    end

    return vx, vy
end

function player:attack()
    -- Check if can attack
    if self.state == "attacking" then
        return false
    end

    if self.attack_cooldown > 0 then
        return false
    end

    -- Start attack
    if self.weapon:startAttack() then
        self.state = "attacking"
        self.attack_cooldown = self.attack_cooldown_max
        return true
    end

    return false
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

function player:drawWeapon()
    -- Draw weapon separately (called after player draw)
    self.weapon:draw(debug.debug_mode)
end

return player

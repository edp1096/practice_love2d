-- entities/player.lua
-- Player entity: handles input, animation, and movement intent with PARRY and DODGE system

local anim8 = require "vendor.anim8"
local debug = require "systems.debug"
local weapon_class = require "entities.weapon"

local player = {}
player.__index = player

-- Debug: Hand position marking mode
local DEBUG_HAND_MARKING = false
local ACTUAL_HAND_POSITIONS = {} -- Store user-clicked hand positions
local DEBUG_MANUAL_FRAME = 1     -- Current frame in manual mode

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
    instance.state = "idle" -- idle, walking, attacking, parrying, dodging
    instance.attack_cooldown = 0
    instance.attack_cooldown_max = 0.5

    -- Weapon sheathing system
    instance.weapon_drawn = false      -- Start with weapon sheathed
    instance.last_action_time = 0
    instance.weapon_sheath_delay = 5.0 -- Sheath weapon after 5 seconds of inactivity

    -- Health system
    instance.max_health = 100
    instance.health = instance.max_health

    -- Hit effects
    instance.hit_flash_timer = 0       -- White flash duration
    instance.hit_shake_x = 0           -- Shake offset X
    instance.hit_shake_y = 0           -- Shake offset Y
    instance.hit_shake_intensity = 6   -- Shake distance (6 pixels)
    instance.invincible_timer = 0      -- Invincibility after hit
    instance.invincible_duration = 1.0 -- 1 second invincibility

    -- Parry system
    instance.parry_active = false          -- Currently in parry stance
    instance.parry_window = 0.3            -- Total parry window duration
    instance.parry_perfect_window = 0.15   -- Perfect parry window (first half)
    instance.parry_timer = 0               -- Current parry timer
    instance.parry_cooldown = 0            -- Cooldown after parry attempt
    instance.parry_cooldown_duration = 1.0 -- Cooldown duration
    instance.parry_success = false         -- Visual feedback flag
    instance.parry_success_timer = 0       -- Success effect duration
    instance.parry_perfect = false         -- Was it a perfect parry?

    -- Dodge/Roll system
    instance.dodge_active = false             -- Currently dodging
    instance.dodge_duration = 0.3             -- Dodge animation duration
    instance.dodge_timer = 0                  -- Current dodge timer
    instance.dodge_cooldown = 0               -- Cooldown between dodges
    instance.dodge_cooldown_duration = 1.0    -- Cooldown duration
    instance.dodge_distance = 150             -- Distance to travel during dodge
    instance.dodge_speed = 0                  -- Current dodge velocity
    instance.dodge_direction_x = 0            -- Dodge direction X
    instance.dodge_direction_y = 0            -- Dodge direction Y
    instance.dodge_invincible_duration = 0.25 -- Invincibility frames duration
    instance.dodge_invincible_timer = 0       -- Current i-frame timer

    -- Facing angle (for weapon direction)
    instance.facing_angle = 0

    return instance
end

function player:update(dt, cam)
    -- Update attack cooldown
    if self.attack_cooldown > 0 then
        self.attack_cooldown = self.attack_cooldown - dt
    end

    -- Update parry cooldown
    if self.parry_cooldown > 0 then
        self.parry_cooldown = self.parry_cooldown - dt
    end

    -- Update dodge cooldown
    if self.dodge_cooldown > 0 then
        self.dodge_cooldown = self.dodge_cooldown - dt
    end

    -- Update dodge state
    if self.dodge_active then
        self.dodge_timer = self.dodge_timer - dt
        if self.dodge_timer <= 0 then
            -- Dodge finished
            self.dodge_active = false
            self.state = "idle"
            self.dodge_speed = 0

            -- Restore collision
            if self.collider then
                self.collider:setSensor(false)
            end
        end
    end

    -- Update dodge invincibility frames
    if self.dodge_invincible_timer > 0 then
        self.dodge_invincible_timer = self.dodge_invincible_timer - dt
    end

    -- Update parry timer
    if self.parry_active then
        self.parry_timer = self.parry_timer - dt
        if self.parry_timer <= 0 then
            -- Parry window expired
            self.parry_active = false
            self.state = "idle"
            self.parry_cooldown = self.parry_cooldown_duration -- Failed parry = cooldown
        end
    end

    -- Update parry success visual effect
    if self.parry_success_timer > 0 then
        self.parry_success_timer = self.parry_success_timer - dt
        if self.parry_success_timer <= 0 then
            self.parry_success = false
            self.parry_perfect = false
        end
    end

    -- Update hit effects
    if self.hit_flash_timer > 0 then
        self.hit_flash_timer = math.max(0, self.hit_flash_timer - dt)
    end

    if self.invincible_timer > 0 then
        self.invincible_timer = math.max(0, self.invincible_timer - dt)
    end

    -- Update shake during hit state
    if self.hit_flash_timer > 0 then
        -- Generate random jitter every frame
        self.hit_shake_x = (math.random() - 0.5) * 2 * self.hit_shake_intensity
        self.hit_shake_y = (math.random() - 0.5) * 2 * self.hit_shake_intensity
    else
        self.hit_shake_x = 0
        self.hit_shake_y = 0
    end


    -- Auto-sheath weapon after inactivity
    if self.weapon_drawn and self.state ~= "attacking" and not self.parry_active then
        self.last_action_time = self.last_action_time + dt
        if self.last_action_time >= self.weapon_sheath_delay then
            self.weapon_drawn = false
            self.weapon:emitSheathParticles() -- Position auto-updated every frame
        end
    end

    -- Direction control based on mode
    if DEBUG_HAND_MARKING then
        -- In hand marking mode: use WASD to control direction (ignore mouse)
        if love.keyboard.isDown('w') then
            self.direction = 'up'
            self.facing_angle = -math.pi / 2
        elseif love.keyboard.isDown('s') then
            self.direction = 'down'
            self.facing_angle = math.pi / 2
        elseif love.keyboard.isDown('a') then
            self.direction = 'left'
            self.facing_angle = math.pi
        elseif love.keyboard.isDown('d') then
            self.direction = 'right'
            self.facing_angle = 0
        end
    elseif self.weapon_drawn or self.parry_active then
        -- Weapon drawn or parrying: use mouse for direction
        local mouse_x, mouse_y
        if cam then
            mouse_x, mouse_y = cam:worldCoords(love.mouse.getPosition())
        else
            mouse_x, mouse_y = love.mouse.getPosition()
        end

        local raw_angle = math.atan2(mouse_y - self.y, mouse_x - self.x)

        -- Snap to 4 directions
        if raw_angle > -math.pi / 4 and raw_angle <= math.pi / 4 then
            self.direction = "right"
            self.facing_angle = 0
        elseif raw_angle > math.pi / 4 and raw_angle <= 3 * math.pi / 4 then
            self.direction = "down"
            self.facing_angle = math.pi / 2
        elseif raw_angle > 3 * math.pi / 4 or raw_angle <= -3 * math.pi / 4 then
            self.direction = "left"
            self.facing_angle = math.pi
        else
            self.direction = "up"
            self.facing_angle = -math.pi / 2
        end
    else
        -- Weapon sheathed: direction follows movement keys
    end

    -- Determine current animation name and frame
    local current_anim_name = nil
    local current_frame_index = 1

    -- Check if attack animation finished
    if self.state == "attacking" and not self.weapon.is_attacking then
        self.state = "idle"
    end

    local is_moving = false
    local vx, vy = 0, 0

    -- Check movement input
    local movement_input = false
    if love.keyboard.isDown("right", "d") or
        love.keyboard.isDown("left", "a") or
        love.keyboard.isDown("down", "s") or
        love.keyboard.isDown("up", "w") then
        movement_input = true
    end

    -- Only allow actual movement if not attacking, not parrying, not dodging, AND not in hand marking mode
    if self.state ~= "attacking" and not self.parry_active and not self.dodge_active and not DEBUG_HAND_MARKING then
        local move_direction = nil

        if love.keyboard.isDown("right", "d") then
            vx = self.speed
            is_moving = true
            move_direction = "right"
        end

        if love.keyboard.isDown("left", "a") then
            vx = -self.speed
            is_moving = true
            move_direction = "left"
        end

        if love.keyboard.isDown("down", "s") then
            vy = self.speed
            is_moving = true
            move_direction = "down"
        end

        if love.keyboard.isDown("up", "w") then
            vy = -self.speed
            is_moving = true
            move_direction = "up"
        end

        -- If weapon is sheathed and not parrying, direction follows movement
        if not self.weapon_drawn and move_direction then
            self.direction = move_direction
            if self.direction == "right" then
                self.facing_angle = 0
            elseif self.direction == "left" then
                self.facing_angle = math.pi
            elseif self.direction == "down" then
                self.facing_angle = math.pi / 2
            elseif self.direction == "up" then
                self.facing_angle = -math.pi / 2
            end
        end

        if is_moving then
            current_anim_name = "walk_" .. self.direction
            self.anim = self.animations[current_anim_name]
            self.anim:update(dt)
            self.state = "walking"
        else
            current_anim_name = "idle_" .. self.direction
            self.anim = self.animations[current_anim_name]
            self.anim:update(dt)
            if self.state ~= "attacking" and not self.parry_active then
                self.state = "idle"
            end
        end
    elseif self.dodge_active then
        -- During dodge, use dodge velocity
        vx = self.dodge_direction_x * self.dodge_speed
        vy = self.dodge_direction_y * self.dodge_speed

        -- Use walk animation during dodge
        current_anim_name = "walk_" .. self.direction
        self.anim = self.animations[current_anim_name]
        self.anim:update(dt * 2) -- Speed up animation during dodge
    elseif self.state == "attacking" then
        current_anim_name = "attack_" .. self.direction
        self.anim = self.animations[current_anim_name]
        if not DEBUG_HAND_MARKING then
            self.anim:update(dt)
        end
    elseif self.parry_active then
        -- During parry, use idle animation with special effect
        current_anim_name = "idle_" .. self.direction
        self.anim = self.animations[current_anim_name]
        self.anim:update(dt)
    elseif DEBUG_HAND_MARKING then
        if movement_input then
            self.state = "walking"
        else
            if self.state ~= "attacking" and not self.parry_active then
                self.state = "idle"
            end
        end

        if self.state == "walking" then
            current_anim_name = "walk_" .. self.direction
        elseif self.state == "attacking" then
            current_anim_name = "attack_" .. self.direction
        else
            current_anim_name = "idle_" .. self.direction
        end

        if not self.anim or self.anim ~= self.animations[current_anim_name] then
            self.anim = self.animations[current_anim_name]
        end
    end

    self.current_anim_name = current_anim_name

    if DEBUG_HAND_MARKING then
        current_frame_index = DEBUG_MANUAL_FRAME
    elseif self.anim and self.anim.position then
        current_frame_index = math.floor(self.anim.position)
    end

    -- Update weapon
    self.weapon:update(dt, self.x, self.y, self.facing_angle,
        self.direction, current_anim_name, current_frame_index, DEBUG_HAND_MARKING)

    return vx, vy
end

function player:attack()
    -- Can't attack while parrying or in parry cooldown
    if self.parry_active or self.parry_cooldown > 0 then
        return false
    end

    if self.state == "attacking" then
        return false
    end

    if self.attack_cooldown > 0 then
        return false
    end

    -- Draw weapon if sheathed
    if not self.weapon_drawn then
        self.weapon_drawn = true
    end

    -- Reset inactivity timer
    self.last_action_time = 0

    -- Start attack
    if self.weapon:startAttack() then
        self.state = "attacking"
        self.attack_cooldown = self.attack_cooldown_max
        return true
    end

    return false
end

function player:startParry()
    -- Check if can parry
    if self.parry_cooldown > 0 then
        return false -- On cooldown
    end

    if self.state == "attacking" then
        return false -- Can't parry while attacking
    end

    if self.parry_active then
        return false -- Already parrying
    end

    if self.dodge_active then
        return false -- Can't parry while dodging
    end

    -- Draw weapon if sheathed
    if not self.weapon_drawn then
        self.weapon_drawn = true
    end

    -- Reset inactivity timer
    self.last_action_time = 0

    -- Start parry
    self.parry_active = true
    self.parry_timer = self.parry_window
    self.state = "parrying"

    return true
end

function player:startDodge()
    -- Check if can dodge
    if self.dodge_cooldown > 0 then
        return false -- On cooldown
    end

    if self.state == "attacking" then
        return false -- Can't dodge while attacking
    end

    if self.parry_active then
        return false -- Can't dodge while parrying
    end

    if self.dodge_active then
        return false -- Already dodging
    end

    -- Determine dodge direction based on movement keys
    local dir_x = 0
    local dir_y = 0

    if love.keyboard.isDown("right", "d") then
        dir_x = 1
    end
    if love.keyboard.isDown("left", "a") then
        dir_x = -1
    end
    if love.keyboard.isDown("down", "s") then
        dir_y = 1
    end
    if love.keyboard.isDown("up", "w") then
        dir_y = -1
    end

    -- If no direction pressed, dodge in facing direction
    if dir_x == 0 and dir_y == 0 then
        if self.direction == "right" then
            dir_x = 1
        elseif self.direction == "left" then
            dir_x = -1
        elseif self.direction == "down" then
            dir_y = 1
        elseif self.direction == "up" then
            dir_y = -1
        end
    end

    -- Normalize direction
    local length = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if length > 0 then
        dir_x = dir_x / length
        dir_y = dir_y / length
    end

    -- Update player direction based on dodge
    if math.abs(dir_x) > math.abs(dir_y) then
        if dir_x > 0 then
            self.direction = "right"
        else
            self.direction = "left"
        end
    else
        if dir_y > 0 then
            self.direction = "down"
        else
            self.direction = "up"
        end
    end

    -- Start dodge
    self.dodge_active = true
    self.dodge_timer = self.dodge_duration
    self.dodge_speed = self.dodge_distance / self.dodge_duration
    self.dodge_direction_x = dir_x
    self.dodge_direction_y = dir_y
    self.dodge_cooldown = self.dodge_cooldown_duration
    self.dodge_invincible_timer = self.dodge_invincible_duration
    self.state = "dodging"

    -- Enable sensor mode to pass through enemies
    if self.collider then
        self.collider:setSensor(true)
    end

    -- Reset inactivity timer
    self.last_action_time = 0

    return true
end

function player:checkParry(incoming_damage)
    if not self.parry_active then
        return false, 0 -- Not parrying
    end

    -- Check if within parry window
    local time_elapsed = self.parry_window - self.parry_timer
    local is_perfect = time_elapsed <= self.parry_perfect_window

    -- Successful parry!
    self.parry_active = false
    self.parry_success = true
    self.parry_perfect = is_perfect
    self.parry_success_timer = 0.5 -- Visual effect duration

    -- No cooldown on successful parry
    self.parry_cooldown = 0
    self.state = "idle"

    -- Return parry info
    return true, is_perfect
end

function player:draw()
    -- In hand marking mode, manually set animation frame
    if DEBUG_HAND_MARKING and self.anim then
        local frame_count = #self.anim.frames
        local safe_frame = math.max(1, math.min(DEBUG_MANUAL_FRAME, frame_count))
        self.anim.position = safe_frame
    end

    -- Apply shake to sprite position
    local draw_x = self.x + self.hit_shake_x
    local draw_y = self.y + self.hit_shake_y

    -- Draw shadow
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", draw_x, draw_y + 50, 28, 8)
    love.graphics.setColor(1, 1, 1, 1)

    -- Draw parry shield effect (behind player)
    if self.parry_active then
        local shield_alpha = 0.3 + 0.2 * math.sin(love.timer.getTime() * 10)
        love.graphics.setColor(0.3, 0.6, 1, shield_alpha)
        love.graphics.circle("fill", draw_x, draw_y, 40)
        love.graphics.setColor(0.5, 0.8, 1, 0.6)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", draw_x, draw_y, 40)
        love.graphics.setLineWidth(1)
    end

    -- Draw player sprite with blink effect during invincibility
    local should_draw = true
    if self.invincible_timer > 0 or self.dodge_invincible_timer > 0 then
        local blink_cycle = math.floor(love.timer.getTime() / 0.1)
        should_draw = (blink_cycle % 2 == 0)
    end

    -- Draw dodge afterimages (ghost trail effect)
    if self.dodge_active then
        local progress = 1 - (self.dodge_timer / self.dodge_duration)
        for i = 1, 3 do
            local offset = i * 0.05 -- Time offset for each afterimage
            if progress > offset then
                local alpha = 0.3 - (i * 0.1)
                love.graphics.setColor(1, 1, 1, alpha)

                -- Calculate afterimage position (behind current position)
                local afterimage_x = draw_x - (self.dodge_direction_x * i * 15)
                local afterimage_y = draw_y - (self.dodge_direction_y * i * 15)

                self.anim:draw(self.spriteSheet, afterimage_x, afterimage_y, nil, 3, nil, 24, 24)
            end
        end
    end

    if should_draw then
        -- Draw parry glow effect (additive behind sprite)
        if self.parry_active then
            local glow_alpha = 0.4
            love.graphics.setBlendMode("add")
            love.graphics.setColor(0.3, 0.6, 1, glow_alpha)
            self.anim:draw(self.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)
            love.graphics.setBlendMode("alpha")
        end

        -- Draw normal sprite
        love.graphics.setColor(1, 1, 1, 1)
        self.anim:draw(self.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)

        -- Draw white flash overlay
        if self.hit_flash_timer > 0 then
            local flash_intensity = self.hit_flash_timer / 0.2
            love.graphics.setBlendMode("add")
            love.graphics.setColor(1, 1, 1, flash_intensity * 0.7)
            self.anim:draw(self.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
        end

        -- Draw parry success flash (gold)
        if self.parry_success_timer > 0 then
            local flash_intensity = self.parry_success_timer / 0.5
            love.graphics.setBlendMode("add")
            if self.parry_perfect then
                -- Perfect parry = bright gold
                love.graphics.setColor(1, 1, 0, flash_intensity * 0.9)
            else
                -- Normal parry = blue
                love.graphics.setColor(0.5, 0.8, 1, flash_intensity * 0.7)
            end
            self.anim:draw(self.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- Debug hitbox
    if debug.show_colliders and self.collider then
        love.graphics.setColor(0, 1, 0, 0.3)
        love.graphics.rectangle("fill", self.x - self.width / 2, self.y - self.height / 2, self.width, self.height)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function player:drawWeapon()
    self.weapon:draw(debug.debug_mode)
end

function player:drawAll()
    if not self.weapon_drawn then
        self:draw()
        self.weapon:drawSheathParticles()
        return
    end

    if self.direction == "left" or self.direction == "up" then
        self:drawWeapon()
        self:draw()
        self.weapon:drawSheathParticles()
    else
        self:draw()
        self:drawWeapon()
        self.weapon:drawSheathParticles()
    end
end

function player:toggleHandMarking()
    DEBUG_HAND_MARKING = not DEBUG_HAND_MARKING
    if DEBUG_HAND_MARKING then
        DEBUG_MANUAL_FRAME = 1
        print("=== HAND MARKING MODE ENABLED ===")
        print("Animation PAUSED")
        print("PgUp/PgDown: Previous/Next frame")
        print("P: Mark hand position")
        print("Ctrl+P: Mark weapon anchor")
        print("Current animation: " .. (self.current_anim_name or "unknown"))
        print("Current frame: " .. DEBUG_MANUAL_FRAME)
    else
        print("=== HAND MARKING MODE DISABLED ===")
    end
end

function player:nextFrame()
    if not DEBUG_HAND_MARKING then return end

    local frame_count = self:getFrameCount(self.current_anim_name)
    DEBUG_MANUAL_FRAME = DEBUG_MANUAL_FRAME + 1
    if DEBUG_MANUAL_FRAME > frame_count then
        DEBUG_MANUAL_FRAME = 1
    end
    print(self.current_anim_name .. " Frame: " .. DEBUG_MANUAL_FRAME .. " / " .. frame_count)
end

function player:prevFrame()
    if not DEBUG_HAND_MARKING then return end

    local frame_count = self:getFrameCount(self.current_anim_name)
    DEBUG_MANUAL_FRAME = DEBUG_MANUAL_FRAME - 1
    if DEBUG_MANUAL_FRAME < 1 then
        DEBUG_MANUAL_FRAME = frame_count
    end
    print(self.current_anim_name .. " Frame: " .. DEBUG_MANUAL_FRAME .. " / " .. frame_count)
end

function player:markHandPosition(world_x, world_y)
    if not DEBUG_HAND_MARKING then return end

    local relative_x = world_x - self.x
    local relative_y = world_y - self.y

    local sprite_x = math.floor(relative_x / 3)
    local sprite_y = math.floor(relative_y / 3)

    local anim_name = self.current_anim_name or "idle_right"
    local frame_index = DEBUG_MANUAL_FRAME
    if not DEBUG_HAND_MARKING and self.anim and self.anim.position then
        frame_index = math.floor(self.anim.position)
    end

    local weapon_angle = self.weapon.angle

    if not ACTUAL_HAND_POSITIONS[anim_name] then
        ACTUAL_HAND_POSITIONS[anim_name] = {}
    end
    ACTUAL_HAND_POSITIONS[anim_name][frame_index] = {
        x = sprite_x,
        y = sprite_y,
        angle = weapon_angle
    }

    local angle_str = player:formatAngle(weapon_angle)

    print(string.format("MARKED: %s[%d] = {x = %d, y = %d, angle = %s},",
        anim_name, frame_index, sprite_x, sprite_y, angle_str))

    local frame_count = self:getFrameCount(anim_name)
    local marked_count = 0
    for _ in pairs(ACTUAL_HAND_POSITIONS[anim_name]) do
        marked_count = marked_count + 1
    end

    if marked_count == frame_count then
        print("=== COMPLETE " .. anim_name .. " ===")
        print(anim_name .. " = {")
        for i = 1, frame_count do
            local pos = ACTUAL_HAND_POSITIONS[anim_name][i]
            if pos then
                local angle_str = player:formatAngle(pos.angle)
                print(string.format("    {x = %d, y = %d, angle = %s},",
                    pos.x, pos.y, angle_str))
            end
        end
        print("},")
    end
end

function player:formatAngle(angle)
    if not angle then return "nil" end

    local pi = math.pi
    local tolerance = 0.01

    local angles = {
        { value = 0,           str = "0" },
        { value = pi / 6,      str = "math.pi / 6" },
        { value = pi / 4,      str = "math.pi / 4" },
        { value = pi / 3,      str = "math.pi / 3" },
        { value = pi / 2,      str = "math.pi / 2" },
        { value = pi * 2 / 3,  str = "math.pi * 2 / 3" },
        { value = pi * 3 / 4,  str = "math.pi * 3 / 4" },
        { value = pi * 5 / 6,  str = "math.pi * 5 / 6" },
        { value = pi,          str = "math.pi" },
        { value = -pi / 6,     str = "-math.pi / 6" },
        { value = -pi / 4,     str = "-math.pi / 4" },
        { value = -pi / 3,     str = "-math.pi / 3" },
        { value = -pi / 2,     str = "-math.pi / 2" },
        { value = pi * 5 / 12, str = "math.pi * 5 / 12" },
        { value = pi * 7 / 12, str = "math.pi * 7 / 12" },
    }

    for _, entry in ipairs(angles) do
        if math.abs(angle - entry.value) < tolerance then
            return entry.str
        end
    end

    return string.format("%.4f", angle)
end

function player:markWeaponAnchor(world_x, world_y)
    if not DEBUG_HAND_MARKING then return end

    local weapon_x = self.weapon.x
    local weapon_y = self.weapon.y

    local relative_x = world_x - weapon_x
    local relative_y = world_y - weapon_y

    local sprite_x = math.floor(relative_x / 3) + 8
    local sprite_y = math.floor(relative_y / 3) + 8

    local direction = self.direction or "right"
    print(string.format("WEAPON_HANDLE_ANCHORS.%s = {x = %d, y = %d},",
        direction, sprite_x, sprite_y))
end

function player:getFrameCount(anim_name)
    local counts = {
        idle_right = 4,
        idle_left = 4,
        idle_up = 4,
        idle_down = 4,
        walk_right = 6,
        walk_left = 6,
        walk_up = 4,
        walk_down = 4,
        attack_right = 4,
        attack_left = 4,
        attack_up = 4,
        attack_down = 4
    }
    return counts[anim_name] or 4
end

function player:drawDebug()
    if not debug.debug_mode then return end

    local anim_name = self.current_anim_name or "idle_right"
    local frame_index = 1
    if DEBUG_HAND_MARKING then
        frame_index = DEBUG_MANUAL_FRAME
    elseif self.anim and self.anim.position then
        frame_index = math.floor(self.anim.position)
    end

    if ACTUAL_HAND_POSITIONS[anim_name] and ACTUAL_HAND_POSITIONS[anim_name][frame_index] then
        local pos = ACTUAL_HAND_POSITIONS[anim_name][frame_index]
        local world_x = self.x + (pos.x * 3)
        local world_y = self.y + (pos.y * 3)

        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.circle("fill", world_x, world_y, 6)
        love.graphics.setColor(1, 0, 0, 0.5)
        love.graphics.circle("line", world_x, world_y, 12)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("ACTUAL", world_x - 20, world_y - 25)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function player:isHandMarkingMode()
    return DEBUG_HAND_MARKING
end

function player:getHandMarkingInfo()
    if not DEBUG_HAND_MARKING then return nil end
    return {
        animation = self.current_anim_name,
        frame = DEBUG_MANUAL_FRAME,
        frame_count = self:getFrameCount(self.current_anim_name)
    }
end

function player:takeDamage(damage, shake_callback)
    -- Check parry first
    local parried, is_perfect = self:checkParry(damage)
    if parried then
        -- Parry successful - no damage taken!
        if shake_callback then
            shake_callback(4, 0.1)     -- Small shake for feedback
        end
        return false, true, is_perfect -- Return: damaged, parried, perfect
    end

    -- Check dodge invincibility
    if self.dodge_invincible_timer > 0 then
        print("Dodged attack!")
        return false, false, false -- Dodged the attack
    end

    -- Check invincibility
    if self.invincible_timer > 0 then
        return false, false, false
    end

    -- Apply damage
    self.health = math.max(0, self.health - damage)

    -- Trigger hit effects
    self.hit_flash_timer = 0.2
    self.invincible_timer = self.invincible_duration

    -- Camera shake
    if shake_callback then
        shake_callback(12, 0.3)
    end

    -- Death check
    if self.health <= 0 then
        print("Player died!")
    end

    return true, false, false
end

function player:isAlive()
    return self.health > 0
end

function player:isInvincible()
    return self.invincible_timer > 0
end

function player:isParrying()
    return self.parry_active
end

function player:isDodging()
    return self.dodge_active
end

function player:isDodgeInvincible()
    return self.dodge_invincible_timer > 0
end

return player

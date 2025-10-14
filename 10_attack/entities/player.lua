-- entities/player.lua
-- Player entity: handles input, animation, and movement intent

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
    instance.state = "idle" -- idle, walking, attacking
    instance.attack_cooldown = 0
    instance.attack_cooldown_max = 0.5

    -- Weapon sheathing system
    instance.weapon_drawn = false      -- Start with weapon sheathed
    instance.last_action_time = 0
    instance.weapon_sheath_delay = 5.0 -- Sheath weapon after 5 seconds of inactivity

    -- Facing angle (for weapon direction)
    instance.facing_angle = 0

    return instance
end

function player:update(dt, cam)
    -- Update attack cooldown
    if self.attack_cooldown > 0 then
        self.attack_cooldown = self.attack_cooldown - dt
    end

    -- Auto-sheath weapon after inactivity
    if self.weapon_drawn and self.state ~= "attacking" then
        self.last_action_time = self.last_action_time + dt
        if self.last_action_time >= self.weapon_sheath_delay then
            self.weapon_drawn = false
            self.weapon:emitSheathParticles() -- Position auto-updated every frame
            -- print("Weapon sheathed") -- Debug
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
        -- If no key pressed, keep current direction
    elseif self.weapon_drawn then
        -- Weapon drawn: use mouse for direction
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
            self.facing_angle = 0
        elseif raw_angle > math.pi / 4 and raw_angle <= 3 * math.pi / 4 then
            -- Down (south: 45° to 135°)
            self.direction = "down"
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
    else
        -- Weapon sheathed: direction follows movement keys (traditional controls)
        -- Direction will be updated by movement input below
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

    -- Check movement input (for state tracking even in hand marking mode)
    local movement_input = false
    if love.keyboard.isDown("right", "d") or
        love.keyboard.isDown("left", "a") or
        love.keyboard.isDown("down", "s") or
        love.keyboard.isDown("up", "w") then
        movement_input = true
    end

    -- Only allow actual movement if not attacking AND not in hand marking mode
    if self.state ~= "attacking" and not DEBUG_HAND_MARKING then
        -- Input handling
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

        -- If weapon is sheathed, direction follows movement
        if not self.weapon_drawn and move_direction then
            self.direction = move_direction
            -- Set facing angle based on direction
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
            -- Use walk animation for current direction
            current_anim_name = "walk_" .. self.direction
            self.anim = self.animations[current_anim_name]
            self.anim:update(dt)
            self.state = "walking"
        else
            -- Use idle animation for current direction
            current_anim_name = "idle_" .. self.direction
            self.anim = self.animations[current_anim_name]
            self.anim:update(dt)
            if self.state ~= "attacking" then
                self.state = "idle"
            end
        end
    elseif self.state == "attacking" then
        -- During attack, use proper attack animation
        current_anim_name = "attack_" .. self.direction
        self.anim = self.animations[current_anim_name]
        if not DEBUG_HAND_MARKING then
            self.anim:update(dt)
        end
    elseif DEBUG_HAND_MARKING then
        -- In hand marking mode: update state based on movement input
        if movement_input then
            self.state = "walking"
        else
            if self.state ~= "attacking" then
                self.state = "idle"
            end
        end

        -- Show appropriate animation based on current state
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
        -- Don't update animation - frozen for marking
    end

    -- Store for debug access
    self.current_anim_name = current_anim_name

    -- Extract current frame index from anim8 animation
    -- anim8 position is 1-indexed (1 to frame_count)
    if DEBUG_HAND_MARKING then
        current_frame_index = DEBUG_MANUAL_FRAME
    elseif self.anim and self.anim.position then
        current_frame_index = math.floor(self.anim.position)
    end

    -- Update weapon with animation info
    self.weapon:update(dt, self.x, self.y, self.facing_angle,
        self.direction, current_anim_name, current_frame_index, DEBUG_HAND_MARKING)

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

    -- Draw weapon if sheathed
    if not self.weapon_drawn then
        self.weapon_drawn = true
        -- print("Weapon drawn") -- Debug
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

function player:draw()
    -- In hand marking mode, manually set animation frame
    if DEBUG_HAND_MARKING and self.anim then
        -- anim8 position is 1-indexed (1 to frame_count)
        -- Clamp to valid range
        local frame_count = #self.anim.frames
        local safe_frame = math.max(1, math.min(DEBUG_MANUAL_FRAME, frame_count))
        self.anim.position = safe_frame
    end

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

function player:drawAll()
    if not self.weapon_drawn then
        -- Weapon sheathed: player first, then sheath particles on top
        self:draw()
        self.weapon:drawSheathParticles() -- Draw sheath particles in front of player
        return
    end

    -- Weapon drawn: draw with proper layering
    if self.direction == "left" or self.direction == "up" then
        -- Left/Up: weapon behind player
        self:drawWeapon()
        self:draw()
        self.weapon:drawSheathParticles() -- Always on top
    else
        -- Right/Down: weapon in front of player
        self:draw()
        self:drawWeapon()
        self.weapon:drawSheathParticles() -- Always on top
    end
end

function player:toggleHandMarking()
    DEBUG_HAND_MARKING = not DEBUG_HAND_MARKING
    if DEBUG_HAND_MARKING then
        -- Always start at frame 1
        DEBUG_MANUAL_FRAME = 1
        print("=== HAND MARKING MODE ENABLED ===")
        print("Animation PAUSED")
        print("PgUp/PgDown: Previous/Next frame")
        print("Right Click: Mark hand position")
        print("Move/Attack to change animation, then press H again to pause")
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

    -- Convert world coordinates to sprite-relative coordinates
    local relative_x = world_x - self.x
    local relative_y = world_y - self.y

    -- Convert from scaled (3x) to unscaled sprite coordinates
    local sprite_x = math.floor(relative_x / 3)
    local sprite_y = math.floor(relative_y / 3)

    -- Get current animation name and frame
    local anim_name = self.current_anim_name or "idle_right"
    local frame_index = DEBUG_MANUAL_FRAME
    if not DEBUG_HAND_MARKING and self.anim and self.anim.position then
        frame_index = math.floor(self.anim.position)
    end

    -- Get current weapon angle
    local weapon_angle = self.weapon.angle

    -- Store the actual hand position with angle
    if not ACTUAL_HAND_POSITIONS[anim_name] then
        ACTUAL_HAND_POSITIONS[anim_name] = {}
    end
    ACTUAL_HAND_POSITIONS[anim_name][frame_index] = {
        x = sprite_x,
        y = sprite_y,
        angle = weapon_angle
    }

    -- Convert angle to readable format
    local angle_str = player:formatAngle(weapon_angle)

    -- Print for copying to HAND_ANCHORS
    print(string.format("MARKED: %s[%d] = {x = %d, y = %d, angle = %s},",
        anim_name, frame_index, sprite_x, sprite_y, angle_str))

    -- If we have all frames for this animation, print the complete array
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

    -- Common angle values
    local angles = {
        { value = 0,           str = "0" },
        { value = pi / 6,      str = "math.pi / 6" },      -- 30 degrees
        { value = pi / 4,      str = "math.pi / 4" },      -- 45 degrees
        { value = pi / 3,      str = "math.pi / 3" },      -- 60 degrees
        { value = pi / 2,      str = "math.pi / 2" },      -- 90 degrees
        { value = pi * 2 / 3,  str = "math.pi * 2 / 3" },  -- 120 degrees
        { value = pi * 3 / 4,  str = "math.pi * 3 / 4" },  -- 135 degrees
        { value = pi * 5 / 6,  str = "math.pi * 5 / 6" },  -- 150 degrees
        { value = pi,          str = "math.pi" },          -- 180 degrees
        { value = -pi / 6,     str = "-math.pi / 6" },     -- -30 degrees
        { value = -pi / 4,     str = "-math.pi / 4" },     -- -45 degrees
        { value = -pi / 3,     str = "-math.pi / 3" },     -- -60 degrees
        { value = -pi / 2,     str = "-math.pi / 2" },     -- -90 degrees
        { value = pi * 5 / 12, str = "math.pi * 5 / 12" }, -- 75 degrees
        { value = pi * 7 / 12, str = "math.pi * 7 / 12" }, -- 105 degrees
    }

    -- Check if angle matches any common value
    for _, entry in ipairs(angles) do
        if math.abs(angle - entry.value) < tolerance then
            return entry.str
        end
    end

    -- If not a common value, return as decimal
    return string.format("%.4f", angle)
end

function player:markWeaponAnchor(world_x, world_y)
    if not DEBUG_HAND_MARKING then return end

    -- Get weapon position
    local weapon_x = self.weapon.x
    local weapon_y = self.weapon.y

    -- Convert to weapon sprite-relative coordinates
    local relative_x = world_x - weapon_x
    local relative_y = world_y - weapon_y

    -- Convert from scaled (3x) to unscaled sprite coordinates
    -- Weapon sprite is 16x16, scaled by 3, drawn with center origin (8, 8)
    local sprite_x = math.floor(relative_x / 3) + 8
    local sprite_y = math.floor(relative_y / 3) + 8

    -- Print with current direction
    local direction = self.direction or "right"
    print(string.format("WEAPON_HANDLE_ANCHORS.%s = {x = %d, y = %d},",
        direction, sprite_x, sprite_y))
end

function player:getFrameCount(anim_name)
    -- Return expected frame count for each animation
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

    -- Draw actual marked hand positions (RED)
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

        -- RED circle for actual hand position
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.circle("fill", world_x, world_y, 6)
        love.graphics.setColor(1, 0, 0, 0.5)
        love.graphics.circle("line", world_x, world_y, 12)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("ACTUAL", world_x - 20, world_y - 25)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Getter for hand marking mode status (for UI display)
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

return player

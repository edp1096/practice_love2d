-- entities/weapon.lua
-- Weapon entity: handles weapon rendering, animation, and hit detection

local weapon = {}
weapon.__index = weapon

-- Hand anchor positions for each animation frame (relative to player sprite center 24,24)
-- These values are ESTIMATES and need adjustment based on actual sprite measurements
local HAND_ANCHORS = {
    -- Idle animations (4 frames each, subtle breathing motion)
    idle_right = {
        { x = -1, y = 7, angle = math.pi / 4 },        -- 45 degrees
        { x = -2, y = 8, angle = math.pi / 4 + 0.05 }, -- Slight tilt
        { x = -2, y = 9, angle = math.pi / 4 },
        { x = -1, y = 9, angle = math.pi / 4 - 0.05 }  -- Slight tilt back
    },
    idle_left = {
        { x = 0, y = 7, angle = math.pi * 3 / 4 },
        { x = 0, y = 6, angle = 2.4062 },
        { x = 0, y = 7, angle = math.pi * 3 / 4 },
        { x = 0, y = 8, angle = 2.3062 },
    },
    idle_down = {
        { x = -6, y = 6, angle = math.pi / 2 }, -- 90 degrees
        { x = -6, y = 6, angle = 1.6208 },
        { x = -5, y = 6, angle = math.pi / 2 },
        { x = -6, y = 8, angle = 1.5208 },
    },
    idle_up = {
        { x = 4, y = 7, angle = -math.pi / 2 },
        { x = 4, y = 6, angle = -1.5208 },
        { x = 4, y = 7, angle = -math.pi / 2 },
        { x = 3, y = 8, angle = -1.6208 },
    },

    -- Walk animations
    walk_right = {
        { x = 6,  y = 5, angle = 0 },                -- Frame 1: Forward (0 degrees)
        { x = 3,  y = 7, angle = math.pi / 6 },      -- Frame 2: Slight forward (30 degrees)
        { x = -6, y = 7, angle = math.pi / 3 },      -- Frame 3: Back (60 degrees)
        { x = -8, y = 7, angle = math.pi * 5 / 12 }, -- Frame 4: Most back (75 degrees)
        { x = -4, y = 7, angle = math.pi / 4 },      -- Frame 5: Mid (45 degrees)
        { x = 3,  y = 7, angle = math.pi / 6 },      -- Frame 6: Forward (30 degrees)
    },
    walk_left = {
        { x = 7,  y = 6, angle = math.pi },          -- Frame 1: Back (180°)
        { x = 4,  y = 6, angle = math.pi * 5 / 6 },  -- Frame 2: Mid-back (150°)
        { x = -5, y = 6, angle = math.pi * 2 / 3 },  -- Frame 3: Forward (120°)
        { x = -8, y = 5, angle = math.pi * 7 / 12 }, -- Frame 4: Most forward (105°)
        { x = -4, y = 7, angle = math.pi * 3 / 4 },  -- Frame 5: Mid (135°)
        { x = 5,  y = 6, angle = math.pi * 5 / 6 },  -- Frame 6: Back (150°)
    },
    walk_down = {
        { x = -5, y = 4, angle = math.pi / 2 }, -- Frame 1: Center (90°)
        { x = -5, y = 5, angle = 1.7708 },      -- Frame 2: Tilt right
        { x = -6, y = 7, angle = 1.3708 },      -- Frame 3: Tilt left
        { x = -4, y = 8, angle = math.pi / 2 }, -- Frame 4: Center
    },
    walk_up = {
        { x = 3, y = 6,  angle = -math.pi / 2 }, -- Frame 1: Center (-90°)
        { x = 1, y = 10, angle = -1.3708 },      -- Frame 2: Tilt right
        { x = 4, y = 6,  angle = -1.7708 },      -- Frame 3: Tilt left
        { x = 5, y = 6,  angle = -math.pi / 2 }, -- Frame 4: Center
    },

    -- Attack animations (4 frames each)
    attack_right = {
        { x = 6,  y = -2, angle = -math.pi / 2 }, -- Frame 1: Preparing (up, -90°)
        { x = 5,  y = -7, angle = -math.pi / 6 }, -- Frame 2: Swinging down (-30°)
        { x = 5,  y = 8,  angle = math.pi / 2 },  -- Frame 3: Maximum reach (down, 90°)
        { x = -2, y = 7,  angle = math.pi / 3 }   -- Frame 4: Recovery (60°)
    },
    attack_left = {
        { x = -7, y = -2, angle = -math.pi / 2 },    -- Frame 1: Preparing (up, -90°)
        { x = -5, y = -8, angle = -2.6180 },         -- Frame 2: Swinging down (-150°)
        { x = -6, y = 8,  angle = math.pi / 2 },     -- Frame 3: Maximum reach (down, 90°)
        { x = 2,  y = 8,  angle = math.pi * 2 / 3 }, -- Frame 4: Recovery (120°)
    },
    attack_down = {
        { x = -6, y = -7,  angle = math.pi * 3 / 2 }, -- Frame 1: Starting from left (270°)
        { x = -7, y = -12, angle = math.pi * 3 / 2 }, -- Frame 2: Middle (270°)
        { x = 2,  y = 10,  angle = math.pi / 2 },     -- Frame 3: Right (90°)
        { x = 2,  y = 6,   angle = math.pi / 6 },     -- Frame 4: Recovery (30°)
    },
    attack_up = {
        { x = 4,  y = -7,  angle = 0 },              -- Frame 1: Starting from right (0°)
        { x = 6,  y = -13, angle = math.pi / 2 },    -- Frame 2: Middle (90°)
        { x = -8, y = 6,   angle = math.pi },        -- Frame 3: Left (180°)
        { x = -4, y = 8,   angle = math.pi * 5 / 6 } -- Frame 4: Recovery (150°)
    }
}

-- Swing direction configurations
local SWING_CONFIGS = {
    right = {
        type = "vertical",          -- Vertical slash (top to bottom)
        start_angle = -math.pi / 2, -- Start from top
        end_angle = math.pi / 2,    -- End at bottom
        flip_x = false              -- No horizontal flip
    },
    left = {
        type = "vertical",
        start_angle = -math.pi / 2,
        end_angle = math.pi / 2,
        flip_x = true -- Flip horizontally for left
    },
    down = {
        type = "horizontal",   -- Horizontal slash (left to right)
        start_angle = math.pi, -- Start from left
        end_angle = 0,         -- End at right
        flip_x = false
    },
    up = {
        type = "horizontal",
        start_angle = 0,     -- Start from right
        end_angle = math.pi, -- End at left
        flip_x = false
    }
}

-- Weapon handle anchor (position on weapon sprite where hand grips)
-- Sprite coordinates: top-left is (0,0), bottom-right is (16,16)
-- Different for each direction because the sword sprite orientation changes
local WEAPON_HANDLE_ANCHORS = {
    right = { x = 13, y = 13 }, -- Default measured value for right
    left  = { x = 13, y = 13 }, -- To be measured
    down  = { x = 13, y = 13 }, -- To be measured
    up    = { x = 13, y = 13 }  -- To be measured
}

-- Weapon type configurations
local WEAPON_TYPES = {
    sword = {
        sprite_file = "assets/images/steel-weapons.png",
        sprite_x = 0,
        sprite_y = 0,
        sprite_w = 16,
        sprite_h = 16,
        scale = 3,

        -- Attack animation properties
        attack_duration = 0.3,
        swing_radius = 35, -- Distance from hand during swing

        -- Damage and range
        damage = 25,
        range = 80,
        knockback = 100,

        -- Hit timing (which portion of animation can hit)
        hit_start = 0.3,
        hit_end = 0.7
    }
}

function weapon:createTrailParticleSystem()
    -- Create elongated particle for slash arc (20x6 white rectangle)
    local particle_data = love.image.newImageData(20, 6)
    particle_data:mapPixel(function(x, y, r, g, b, a)
        -- Create smooth gradient for glowing effect
        local center_y = 3
        local alpha = 1 - (math.abs(y - center_y) / center_y)
        alpha = math.pow(alpha, 0.5) -- Softer falloff for glow
        return 1, 1, 1, alpha
    end)
    local particle_img = love.graphics.newImage(particle_data)

    -- Create particle system for crescent slash trail
    local ps = love.graphics.newParticleSystem(particle_img, 600)
    ps:setParticleLifetime(0.2, 0.35) -- Visible long enough to see arc
    ps:setEmissionRate(0)
    ps:setSizes(3.5, 4, 3.5, 2.5, 0)  -- Large sizes for visible arc

    -- Bright blue-white slash colors
    ps:setColors(
        1, 1, 1, 1,          -- Pure white core
        0.8, 0.95, 1, 1,     -- Very bright cyan
        0.6, 0.85, 1, 0.9,   -- Bright blue
        0.4, 0.7, 0.95, 0.6, -- Medium blue
        0.2, 0.5, 0.8, 0     -- Transparent
    )

    ps:setLinearDamping(25, 35) -- Very high damping - particles stay in place
    ps:setSpeed(5, 10)          -- Minimal movement
    ps:setSpread(0)             -- No spread - precise positioning
    ps:setRotation(0, 0)
    ps:setRelativeRotation(true)

    return ps
end

function weapon:createSheathParticleSystem()
    -- Create larger particle image for sheath effect (12x12 instead of 6x6)
    local particle_data = love.image.newImageData(12, 12)
    particle_data:mapPixel(function(x, y, r, g, b, a)
        -- Create soft circular particle
        local dx = x - 6
        local dy = y - 6
        local dist = math.sqrt(dx * dx + dy * dy)
        local alpha = math.max(0, 1 - dist / 6)
        return 1, 1, 1, alpha
    end)
    local particle_img = love.graphics.newImage(particle_data)

    -- Create particle system for weapon sheathing (light fading effect)
    local ps = love.graphics.newParticleSystem(particle_img, 150) -- More particles
    ps:setParticleLifetime(0.4, 0.8)                              -- Longer lifetime
    ps:setEmissionRate(0)
    ps:setSizes(3, 3.5, 4, 3, 0)                                  -- Much larger sizes

    -- Warm gold/yellow fading to transparent
    ps:setColors(
        1, 1, 0.7, 1,     -- Bright gold
        1, 0.9, 0.5, 0.8, -- Warm yellow
        1, 0.8, 0.3, 0.5, -- Orange tint
        0.9, 0.7, 0.2, 0.2,
        0.8, 0.6, 0.1, 0  -- Fade to transparent
    )

    ps:setLinearDamping(1, 3) -- Slower damping for wider spread
    ps:setSpeed(30, 80)       -- Faster initial speed
    ps:setSpread(math.pi * 2) -- Radial emission
    ps:setRotation(0, 2 * math.pi)
    ps:setRelativeRotation(false)

    return ps
end

function weapon:new(weapon_type)
    local instance = setmetatable({}, weapon)

    weapon_type = weapon_type or "sword"
    local config = WEAPON_TYPES[weapon_type]

    if not config then
        error("Unknown weapon type: " .. tostring(weapon_type))
    end

    instance.type = weapon_type
    instance.config = config

    -- Load sprite
    instance.sprite_sheet = love.graphics.newImage(config.sprite_file)
    instance.sprite_quad = love.graphics.newQuad(
        config.sprite_x,
        config.sprite_y,
        config.sprite_w,
        config.sprite_h,
        instance.sprite_sheet:getWidth(),
        instance.sprite_sheet:getHeight()
    )

    -- Position and rotation
    instance.x = 0
    instance.y = 0
    instance.angle = 0
    instance.owner_x = 0 -- Player position for particle tracking
    instance.owner_y = 0

    -- Attack state
    instance.is_attacking = false
    instance.attack_progress = 0
    instance.current_swing_angle = 0
    instance.current_direction = "right"

    -- Hit detection
    instance.has_hit = false
    instance.hit_enemies = {}

    -- Particle systems
    instance.trail_particles = instance:createTrailParticleSystem()   -- Sword slash trail
    instance.sheath_particles = instance:createSheathParticleSystem() -- Weapon sheathing effect
    instance.last_particle_x = 0
    instance.last_particle_y = 0

    -- Debug visualization
    instance.debug_hand_x = 0
    instance.debug_hand_y = 0

    return instance
end

function weapon:getHandPosition(owner_x, owner_y, anim_name, frame_index)
    -- Get hand anchor for current animation and frame
    local anchors = HAND_ANCHORS[anim_name]

    if not anchors then
        -- Fallback to default if animation not found
        return owner_x + 10, owner_y + 18, nil
    end

    -- Clamp frame index to valid range
    frame_index = math.max(1, math.min(frame_index, #anchors))
    local anchor = anchors[frame_index]

    -- Convert from sprite-relative to world coordinates
    -- Player sprite is drawn with origin at (24, 24), scaled by 3
    local hand_x = owner_x + (anchor.x * 3)
    local hand_y = owner_y + (anchor.y * 3)

    -- Return angle if specified in anchor data
    local angle = anchor.angle

    return hand_x, hand_y, angle
end

function weapon:update(dt, owner_x, owner_y, owner_angle, direction, anim_name, frame_index, hand_marking_mode)
    -- Store current direction and player position
    self.current_direction = direction or "right"
    self.owner_x = owner_x
    self.owner_y = owner_y

    -- Get current hand position and angle based on animation frame
    local hand_x, hand_y, hand_angle = self:getHandPosition(owner_x, owner_y, anim_name, frame_index)

    -- Store for debug visualization
    self.debug_hand_x = hand_x
    self.debug_hand_y = hand_y

    if self.is_attacking then
        -- Update attack animation (but freeze in hand marking mode)
        if not hand_marking_mode then
            self.attack_progress = self.attack_progress + dt / self.config.attack_duration
        end

        if self.attack_progress >= 1 then
            self:endAttack()
        else
            -- Get swing configuration for current direction
            local swing_config = SWING_CONFIGS[self.current_direction]

            -- Use hand_angle if specified, otherwise calculate interpolated angle
            if hand_angle then
                -- Use frame-specific angle from HAND_ANCHORS
                self.angle = hand_angle
                self.current_swing_angle = hand_angle
            else
                -- Calculate swing progress with easing
                local t = self.attack_progress
                local eased = 1 - math.pow(1 - t, 3) -- Ease out cubic

                -- Calculate current swing angle
                self.current_swing_angle = swing_config.start_angle +
                    (swing_config.end_angle - swing_config.start_angle) * eased

                -- Set weapon sprite angle to match swing direction
                self.angle = self.current_swing_angle
            end

            -- Calculate offset from weapon center to handle (direction-specific)
            local handle_anchor = WEAPON_HANDLE_ANCHORS[self.current_direction] or WEAPON_HANDLE_ANCHORS.right
            local swing_config = SWING_CONFIGS[self.current_direction]

            -- Apply flip to handle anchor if sprite is flipped
            local handle_x = handle_anchor.x
            if swing_config and swing_config.flip_x then
                handle_x = self.config.sprite_w - handle_anchor.x
            end

            local handle_offset_x = (handle_x - self.config.sprite_w / 2)
            local handle_offset_y = (handle_anchor.y - self.config.sprite_h / 2)

            -- Rotate handle offset by weapon angle (including the +90deg sprite rotation)
            local actual_angle = self.angle + math.pi / 2
            local cos_angle = math.cos(actual_angle)
            local sin_angle = math.sin(actual_angle)
            local rotated_offset_x = handle_offset_x * cos_angle - handle_offset_y * sin_angle
            local rotated_offset_y = handle_offset_x * sin_angle + handle_offset_y * cos_angle

            -- Position weapon center so that rotated handle aligns with hand
            self.x = hand_x - (rotated_offset_x * self.config.scale)
            self.y = hand_y - (rotated_offset_y * self.config.scale)

            -- Emit trail particles (but not in hand marking mode)
            if not hand_marking_mode then
                self:emitTrailParticles(dt)
            end
        end
    else
        -- Idle/walking: weapon stays at hand position
        -- Calculate offset from weapon center to handle (direction-specific)
        local handle_anchor = WEAPON_HANDLE_ANCHORS[self.current_direction] or WEAPON_HANDLE_ANCHORS.right
        local swing_config = SWING_CONFIGS[self.current_direction]

        -- Apply flip to handle anchor if sprite is flipped
        local handle_x = handle_anchor.x
        if swing_config and swing_config.flip_x then
            handle_x = self.config.sprite_w - handle_anchor.x
        end

        local handle_offset_x = (handle_x - self.config.sprite_w / 2)
        local handle_offset_y = (handle_anchor.y - self.config.sprite_h / 2)

        -- Set idle angle based on direction
        -- Use angle from HAND_ANCHORS if specified, otherwise use default based on direction
        if hand_angle then
            self.angle = hand_angle
        elseif self.current_direction == "right" then
            self.angle = math.pi / 4
        elseif self.current_direction == "left" then
            self.angle = 3 * math.pi / 4
        elseif self.current_direction == "down" then
            self.angle = math.pi / 2
        elseif self.current_direction == "up" then
            self.angle = -math.pi / 2
        end

        -- Rotate handle offset by weapon angle (including the +90deg sprite rotation)
        local actual_angle = self.angle + math.pi / 2
        local cos_angle = math.cos(actual_angle)
        local sin_angle = math.sin(actual_angle)
        local rotated_offset_x = handle_offset_x * cos_angle - handle_offset_y * sin_angle
        local rotated_offset_y = handle_offset_x * sin_angle + handle_offset_y * cos_angle

        -- Position weapon center so that rotated handle aligns with hand
        self.x = hand_x - (rotated_offset_x * self.config.scale)
        self.y = hand_y - (rotated_offset_y * self.config.scale)

        self.current_swing_angle = 0
    end

    -- Update particle systems
    self.trail_particles:update(dt)
    self.sheath_particles:update(dt)
end

function weapon:emitTrailParticles(dt)
    -- Only emit during middle portion of attack
    if self.attack_progress < 0.2 or self.attack_progress > 0.8 then
        return
    end

    -- Simple test: emit particles at weapon position
    local emission_rate = 1000
    local particles_this_frame = emission_rate * dt

    self.trail_particles:setPosition(self.x, self.y)
    self.trail_particles:setDirection(0)
    self.trail_particles:setSpread(math.pi * 2) -- All directions
    self.trail_particles:emit(particles_this_frame)

    print(string.format("  EMITTED %.1f particles at (%.1f, %.1f)", particles_this_frame, self.x, self.y))
end

function weapon:emitSheathParticles()
    -- Emit particles at origin (offset applied during drawing)
    self.sheath_particles:setPosition(0, 0)
    self.sheath_particles:emit(80) -- Burst of particles
end

function weapon:startAttack()
    if self.is_attacking then
        return false
    end

    self.is_attacking = true
    self.attack_progress = 0
    self.has_hit = false
    self.hit_enemies = {}
    self.trail_particles:reset()

    return true
end

function weapon:endAttack()
    self.is_attacking = false
    self.attack_progress = 0
    self.current_swing_angle = 0
    self.has_hit = false
    self.hit_enemies = {}
end

function weapon:canDealDamage()
    if not self.is_attacking then
        return false
    end

    return self.attack_progress >= self.config.hit_start and
        self.attack_progress <= self.config.hit_end
end

function weapon:getHitbox()
    if not self:canDealDamage() then
        return nil
    end

    return {
        x = self.x,
        y = self.y,
        radius = self.config.range
    }
end

function weapon:checkHit(enemy)
    if self.hit_enemies[enemy] then
        return false
    end

    if not self:canDealDamage() then
        return false
    end

    local hitbox = self:getHitbox()
    if not hitbox then
        return false
    end

    local enemy_x = enemy.x + enemy.collider_offset_x
    local enemy_y = enemy.y + enemy.collider_offset_y

    local dx = enemy_x - hitbox.x
    local dy = enemy_y - hitbox.y
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance < hitbox.radius + enemy.collider_width / 2 then
        self.hit_enemies[enemy] = true
        return true
    end

    return false
end

function weapon:getDamage()
    return self.config.damage
end

function weapon:getKnockback()
    return self.config.knockback
end

function weapon:drawSheathParticles()
    -- Draw sheath particles at player position (follows player movement)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.sheath_particles, self.owner_x, self.owner_y)
    love.graphics.setColor(1, 1, 1, 1)
end

function weapon:draw(debug_mode)
    if not self.sprite_sheet then
        return
    end

    -- Draw trail particle effects
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.trail_particles, 0, 0)

    -- Determine sprite flip based on direction
    local swing_config = SWING_CONFIGS[self.current_direction]
    local scale_x = self.config.scale
    if swing_config and swing_config.flip_x then
        scale_x = -scale_x
    end

    -- Draw weapon sprite
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        self.sprite_sheet,
        self.sprite_quad,
        self.x,
        self.y,
        self.angle + math.pi / 2, -- Add 90 degrees CW rotation
        scale_x,
        self.config.scale,
        self.config.sprite_w / 2,
        self.config.sprite_h / 2
    )

    -- Debug visualization - ALWAYS SHOW ALL MARKERS
    if debug_mode then
        -- Hand position (YELLOW) - where hand should be according to HAND_ANCHORS
        if self.debug_hand_x and self.debug_hand_y then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.circle("fill", self.debug_hand_x, self.debug_hand_y, 8)
            love.graphics.setColor(1, 1, 0, 0.3)
            love.graphics.circle("line", self.debug_hand_x, self.debug_hand_y, 15)

            -- Label
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.print("HAND", self.debug_hand_x - 15, self.debug_hand_y - 25)
        end

        -- Weapon center (GREEN) - where weapon center actually is
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.circle("fill", self.x, self.y, 6)
        love.graphics.setColor(0, 1, 0, 0.3)
        love.graphics.circle("line", self.x, self.y, 12)

        -- Label
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.print("CENTER", self.x - 20, self.y + 20)

        -- Weapon handle (CYAN) - where handle actually is after rotation (direction-specific)
        local handle_anchor = WEAPON_HANDLE_ANCHORS[self.current_direction] or WEAPON_HANDLE_ANCHORS.right
        local swing_config = SWING_CONFIGS[self.current_direction]

        -- Apply flip to handle anchor if sprite is flipped
        local handle_x = handle_anchor.x
        if swing_config and swing_config.flip_x then
            handle_x = self.config.sprite_w - handle_anchor.x
        end

        local handle_offset_x = (handle_x - self.config.sprite_w / 2)
        local handle_offset_y = (handle_anchor.y - self.config.sprite_h / 2)
        local actual_angle = self.angle + math.pi / 2
        local cos_angle = math.cos(actual_angle)
        local sin_angle = math.sin(actual_angle)
        local rotated_offset_x = handle_offset_x * cos_angle - handle_offset_y * sin_angle
        local rotated_offset_y = handle_offset_x * sin_angle + handle_offset_y * cos_angle
        local handle_world_x = self.x + (rotated_offset_x * self.config.scale)
        local handle_world_y = self.y + (rotated_offset_y * self.config.scale)

        love.graphics.setColor(0, 1, 1, 1) -- Bright cyan
        love.graphics.circle("fill", handle_world_x, handle_world_y, 10)
        love.graphics.setColor(0, 1, 1, 0.5)
        love.graphics.circle("line", handle_world_x, handle_world_y, 18)

        -- Label
        love.graphics.setColor(0, 1, 1, 1)
        love.graphics.print("HANDLE", handle_world_x - 22, handle_world_y - 30)

        -- Draw line connecting hand to weapon handle
        if self.debug_hand_x and self.debug_hand_y then
            love.graphics.setColor(1, 0, 1, 0.9) -- Bright magenta
            love.graphics.setLineWidth(3)
            love.graphics.line(self.debug_hand_x, self.debug_hand_y, handle_world_x, handle_world_y)
            love.graphics.setLineWidth(1)
        end

        -- Attack hitbox (only during attack)
        if self.is_attacking then
            local hitbox = self:getHitbox()
            if hitbox and self:canDealDamage() then
                love.graphics.setColor(1, 0, 0, 0.3)
                love.graphics.circle("fill", hitbox.x, hitbox.y, hitbox.radius)
                love.graphics.setColor(1, 0, 0, 0.8)
                love.graphics.circle("line", hitbox.x, hitbox.y, hitbox.radius)
            end
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return weapon

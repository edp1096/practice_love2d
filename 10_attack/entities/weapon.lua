-- entities/weapon.lua
-- Weapon entity: handles weapon rendering, animation, and hit detection

local weapon = {}
weapon.__index = weapon

-- Weapon type configurations
local WEAPON_TYPES = {
    sword = {
        sprite_file = "assets/images/steel-weapons.png",
        sprite_x = 0,  -- X position in sprite sheet
        sprite_y = 0,  -- Y position in sprite sheet
        sprite_w = 16, -- Width of weapon sprite
        sprite_h = 16, -- Height of weapon sprite
        scale = 3,

        -- Attachment point relative to player
        -- attach_offset_x = 25, -- Adjusted for better hand position
        -- attach_offset_y = -5, -- Adjusted for better hand position
        attach_offset_x = 20,
        attach_offset_y = 5,

        -- Attack animation properties
        attack_duration = 0.3,
        -- swing_start_angle = -math.pi / 2, -- Start angle (relative to player direction)
        -- swing_end_angle = math.pi / 2,    -- End angle
        swing_start_angle = math.pi / 2, -- Start angle (relative to player direction)
        swing_end_angle = -math.pi / 2,    -- End angle

        -- Damage and range
        damage = 25,
        range = 80, -- Increased range to cover 3 directions
        knockback = 100,

        -- Hit timing (which portion of animation can hit)
        hit_start = 0.3, -- 30% through animation
        hit_end = 0.7    -- 70% through animation
    }
}

function weapon:createParticleSystem()
    -- Create particle image (4x4 white pixel)
    local particle_data = love.image.newImageData(4, 4)
    particle_data:mapPixel(function(x, y, r, g, b, a)
        return 1, 1, 1, 1 -- White pixel
    end)
    local particle_img = love.graphics.newImage(particle_data)

    -- Create particle system for sword trail
    local ps = love.graphics.newParticleSystem(particle_img, 200)
    ps:setParticleLifetime(0.1, 0.25) -- Short lifetime for quick dissipation
    ps:setEmissionRate(0)             -- We'll emit manually during attack
    ps:setSizes(3, 2.5, 2, 1, 0)      -- Gradual size decrease
    ps:setColors(
        0.6, 0.9, 1, 1,               -- Start: bright cyan
        0.5, 0.85, 1, 0.8,            -- Bright
        0.4, 0.75, 0.95, 0.5,         -- Fading
        0.3, 0.65, 0.9, 0.2,          -- More fade
        0.2, 0.55, 0.85, 0            -- End: transparent
    )
    ps:setLinearDamping(3, 6)         -- Slow down particles quickly
    ps:setSpeed(20, 60)               -- Moderate speed
    ps:setSpread(math.pi / 10)        -- Narrow spread for focused trail
    ps:setRotation(0, 2 * math.pi)
    ps:setRelativeRotation(true)

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
    instance.base_angle = 0 -- Player's facing direction

    -- Attack state
    instance.is_attacking = false
    instance.attack_progress = 0
    instance.current_swing_angle = 0

    -- Hit detection
    instance.has_hit = false  -- Prevent multiple hits in one swing
    instance.hit_enemies = {} -- Track which enemies were hit this swing

    -- Particle system for slash effect
    instance.particle_system = instance:createParticleSystem()
    instance.last_particle_x = 0
    instance.last_particle_y = 0

    return instance
end

function weapon:update(dt, owner_x, owner_y, owner_angle)
    -- Owner_angle is now fixed to 4 directions: 0, π/2, π, -π/2
    self.base_angle = owner_angle

    -- Calculate attachment position based on direction
    -- local attach_x = owner_x + math.cos(owner_angle) * self.config.attach_offset_x
    -- local attach_y = owner_y + math.sin(owner_angle) * self.config.attach_offset_y
    local attach_x = owner_x + self.config.attach_offset_x
    local attach_y = owner_y + self.config.attach_offset_y

    if self.is_attacking then
        -- Update attack animation
        self.attack_progress = self.attack_progress + dt / self.config.attack_duration

        if self.attack_progress >= 1 then
            -- Attack finished
            self:endAttack()
        else
            -- Calculate swing arc using easing function
            local t = self.attack_progress
            -- Ease out cubic for smooth deceleration
            local eased = 1 - math.pow(1 - t, 3)

            -- Interpolate swing angle (relative to base direction)
            self.current_swing_angle = self.config.swing_start_angle +
                (self.config.swing_end_angle - self.config.swing_start_angle) * eased

            -- Position weapon along swing arc
            local swing_radius = 35
            self.x = attach_x + math.cos(owner_angle + self.current_swing_angle) * swing_radius
            self.y = attach_y + math.sin(owner_angle + self.current_swing_angle) * swing_radius

            -- Weapon sprite angle (fixed to base direction + swing offset)
            self.angle = owner_angle + self.current_swing_angle + math.pi / 4

            -- Emit particles along weapon trail
            self:emitTrailParticles(dt)
        end
    else
        -- Idle position (weapon at player's side, fixed to 4 directions)
        self.x = attach_x
        self.y = attach_y
        self.angle = owner_angle -- Fixed angle (no free rotation)
        self.current_swing_angle = 0
    end

    -- Update particle system
    self.particle_system:update(dt)
end

function weapon:emitTrailParticles(dt)
    -- Emit particles along the weapon's path during swing
    if self.attack_progress < 0.1 or self.attack_progress > 0.9 then
        return -- Don't emit at very start or end
    end

    -- Calculate emission intensity based on swing speed
    local emission_rate = 800 -- Particles per second
    local particles_this_frame = emission_rate * dt

    -- Set particle system position to weapon tip
    local tip_offset = 25 -- Distance to weapon tip
    local tip_x = self.x + math.cos(self.angle) * tip_offset
    local tip_y = self.y + math.sin(self.angle) * tip_offset

    -- Set direction for particle emission (perpendicular to swing)
    self.particle_system:setDirection(self.angle + math.pi / 2)

    -- Emit particles
    self.particle_system:setPosition(tip_x, tip_y)
    self.particle_system:emit(particles_this_frame)

    self.last_particle_x = tip_x
    self.last_particle_y = tip_y
end

function weapon:startAttack()
    if self.is_attacking then
        return false -- Already attacking
    end

    self.is_attacking = true
    self.attack_progress = 0
    self.has_hit = false
    self.hit_enemies = {}

    -- Reset particle system
    self.particle_system:reset()

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
    -- Only deal damage during specific portion of swing
    if not self.is_attacking then
        return false
    end

    return self.attack_progress >= self.config.hit_start and
        self.attack_progress <= self.config.hit_end
end

function weapon:getHitbox()
    -- Return circular hitbox for collision detection
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
    -- Check if already hit this enemy in current swing
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

    -- Get enemy center position with offset
    local enemy_x = enemy.x + enemy.collider_offset_x
    local enemy_y = enemy.y + enemy.collider_offset_y

    -- Circle collision detection
    local dx = enemy_x - hitbox.x
    local dy = enemy_y - hitbox.y
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance < hitbox.radius + enemy.collider_width / 2 then
        -- Mark this enemy as hit
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

function weapon:draw(debug_mode)
    if not self.sprite_sheet then
        return
    end

    -- Draw particle slash effect BEFORE weapon sprite
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.particle_system, 0, 0)

    -- Draw weapon sprite
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(
        self.sprite_sheet,
        self.sprite_quad,
        self.x,
        self.y,
        self.angle,
        self.config.scale,
        self.config.scale,
        self.config.sprite_w / 2, -- Origin at center
        self.config.sprite_h / 2
    )

    -- Debug: Draw hitbox when attacking
    if debug_mode and self.is_attacking then
        local hitbox = self:getHitbox()
        if hitbox and self:canDealDamage() then
            love.graphics.setColor(1, 0, 0, 0.3)
            love.graphics.circle("fill", hitbox.x, hitbox.y, hitbox.radius)
            love.graphics.setColor(1, 0, 0, 0.8)
            love.graphics.circle("line", hitbox.x, hitbox.y, hitbox.radius)
        end

        -- Draw weapon center point
        love.graphics.setColor(0, 1, 0, 1)
        love.graphics.circle("fill", self.x, self.y, 3)

        -- Draw particle emission point
        if self.is_attacking then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.circle("fill", self.last_particle_x, self.last_particle_y, 2)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return weapon

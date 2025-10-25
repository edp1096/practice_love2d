-- entities/weapon/init.lua
-- Main weapon module: coordinates combat, rendering, and configuration

local anim8 = require "vendor.anim8"
local combat = require "entities.weapon.combat"
local render = require "entities.weapon.render"
local hand_anchors = require "entities.weapon.config.hand_anchors"
local swing_configs = require "entities.weapon.config.swing_configs"
local handle_anchors = require "entities.weapon.config.handle_anchors"
local sword_types = require "entities.weapon.types.sword"

local weapon = {}
weapon.__index = weapon

function weapon:new(weapon_type)
    local instance = setmetatable({}, weapon)

    weapon_type = weapon_type or "sword"
    local config = sword_types.WEAPON_TYPES[weapon_type]

    if not config then
        error("Unknown weapon type: " .. tostring(weapon_type))
    end

    instance.type = weapon_type
    instance.config = config

    -- Load weapon sprite
    instance.sprite_sheet = love.graphics.newImage(config.sprite_file)
    instance.sprite_quad = love.graphics.newQuad(
        config.sprite_x,
        config.sprite_y,
        config.sprite_w,
        config.sprite_h,
        instance.sprite_sheet:getWidth(),
        instance.sprite_sheet:getHeight()
    )

    -- Load slash effect sprite
    instance.slash_sprite = love.graphics.newImage("assets/images/effect-slash.png")
    instance.slash_grid = anim8.newGrid(23, 39, 46, 39)
    instance.slash_scale = 3

    -- Slash effect state
    instance.slash_active = false
    instance.slash_anim = nil
    instance.slash_x = 0
    instance.slash_y = 0
    instance.slash_rotation = 0
    instance.slash_flip_y = 1

    -- Position and rotation
    instance.x = 0
    instance.y = 0
    instance.angle = 0
    instance.owner_x = 0
    instance.owner_y = 0

    -- Attack state
    instance.is_attacking = false
    instance.attack_progress = 0
    instance.current_swing_angle = 0
    instance.current_direction = "right"

    -- Hit detection
    instance.has_hit = false
    instance.hit_enemies = {}

    -- Sheath particles
    instance.sheath_particles = render.createSheathParticleSystem()

    -- Debug
    instance.debug_hand_x = 0
    instance.debug_hand_y = 0

    return instance
end

function weapon:getHandPosition(owner_x, owner_y, anim_name, frame_index)
    local anchors = hand_anchors.HAND_ANCHORS[anim_name]

    if not anchors then
        return owner_x + 10, owner_y + 18, nil
    end

    frame_index = math.max(1, math.min(frame_index, #anchors))
    local anchor = anchors[frame_index]

    local hand_x = owner_x + (anchor.x * 3)
    local hand_y = owner_y + (anchor.y * 3)
    local angle = anchor.angle

    return hand_x, hand_y, angle
end

function weapon:update(dt, owner_x, owner_y, owner_angle, direction, anim_name, frame_index, hand_marking_mode)
    self.current_direction = direction or "right"
    self.owner_x = owner_x
    self.owner_y = owner_y

    -- Get hand position
    local hand_x, hand_y, hand_angle = self:getHandPosition(owner_x, owner_y, anim_name, frame_index)
    self.debug_hand_x = hand_x
    self.debug_hand_y = hand_y

    if self.is_attacking then
        -- Update attack animation
        if not hand_marking_mode then
            self.attack_progress = self.attack_progress + dt / self.config.attack_duration
        end

        if self.attack_progress >= 1 then
            combat.endAttack(self)
        else
            -- Get swing config
            local swing_config = swing_configs.SWING_CONFIGS[self.current_direction]

            -- Use hand_angle if specified
            if hand_angle then
                self.angle = hand_angle
                self.current_swing_angle = hand_angle
            else
                -- Calculate swing with easing
                local t = self.attack_progress
                local eased = 1 - math.pow(1 - t, 3)

                self.current_swing_angle = swing_config.start_angle +
                    (swing_config.end_angle - swing_config.start_angle) * eased

                self.angle = self.current_swing_angle
            end

            -- Calculate handle offset
            local handle_anchor = handle_anchors.WEAPON_HANDLE_ANCHORS[self.current_direction] or handle_anchors.WEAPON_HANDLE_ANCHORS.right
            local swing_config = swing_configs.SWING_CONFIGS[self.current_direction]

            local handle_x = handle_anchor.x
            local handle_y = handle_anchor.y

            -- Diagonal flip: mirror both X and Y
            if swing_config and swing_config.flip_x then
                handle_x = self.config.sprite_w - handle_anchor.x
                handle_y = self.config.sprite_h - handle_anchor.y
            end

            local handle_offset_x = (handle_x - self.config.sprite_w / 2)
            local handle_offset_y = (handle_y - self.config.sprite_h / 2)

            -- Rotate handle offset
            local actual_angle = self.angle + math.pi / 2
            local cos_angle = math.cos(actual_angle)
            local sin_angle = math.sin(actual_angle)
            local rotated_offset_x = handle_offset_x * cos_angle - handle_offset_y * sin_angle
            local rotated_offset_y = handle_offset_x * sin_angle + handle_offset_y * cos_angle

            -- Position weapon
            self.x = hand_x - (rotated_offset_x * self.config.scale)
            self.y = hand_y - (rotated_offset_y * self.config.scale)
        end
    else
        -- Idle/walking state
        local handle_anchor = handle_anchors.WEAPON_HANDLE_ANCHORS[self.current_direction] or handle_anchors.WEAPON_HANDLE_ANCHORS.right
        local swing_config = swing_configs.SWING_CONFIGS[self.current_direction]

        local handle_x = handle_anchor.x
        local handle_y = handle_anchor.y

        -- Diagonal flip: mirror both X and Y
        if swing_config and swing_config.flip_x then
            handle_x = self.config.sprite_w - handle_anchor.x
            handle_y = self.config.sprite_h - handle_anchor.y
        end

        local handle_offset_x = (handle_x - self.config.sprite_w / 2)
        local handle_offset_y = (handle_y - self.config.sprite_h / 2)

        -- Set idle angle
        if hand_angle then
            -- self.angle = hand_angle
            self.angle = math.pi / 4
        elseif self.current_direction == "right" then
            self.angle = math.pi / 4 -- not reached
        elseif self.current_direction == "left" then
            self.angle = 3 * math.pi / 4
        elseif self.current_direction == "down" then
            self.angle = math.pi / 2
        elseif self.current_direction == "up" then
            self.angle = -math.pi / 2
        end

        -- Rotate handle offset
        local actual_angle = self.angle + math.pi / 2
        local cos_angle = math.cos(actual_angle)
        local sin_angle = math.sin(actual_angle)
        local rotated_offset_x = handle_offset_x * cos_angle - handle_offset_y * sin_angle
        local rotated_offset_y = handle_offset_x * sin_angle + handle_offset_y * cos_angle

        -- Position weapon
        self.x = hand_x - (rotated_offset_x * self.config.scale)
        self.y = hand_y - (rotated_offset_y * self.config.scale)

        self.current_swing_angle = 0
    end

    -- Update slash animation
    if self.slash_active and self.slash_anim then
        if not hand_marking_mode then
            self.slash_anim:update(dt)
        end
    end

    -- Update particles
    self.sheath_particles:update(dt)
end

function weapon:emitSheathParticles()
    self.sheath_particles:setPosition(0, 0)
    self.sheath_particles:emit(80)
end

function weapon:startAttack()
    return combat.startAttack(self)
end

function weapon:canDealDamage()
    return combat.canDealDamage(self)
end

function weapon:getHitbox()
    return combat.getHitbox(self)
end

function weapon:checkHit(enemy)
    return combat.checkHit(self, enemy)
end

function weapon:getDamage()
    return combat.getDamage(self)
end

function weapon:getKnockback()
    return combat.getKnockback(self)
end

function weapon:draw(debug_mode)
    render.draw(self, debug_mode, swing_configs.SWING_CONFIGS)
end

function weapon:drawSheathParticles()
    render.drawSheathParticles(self)
end

return weapon

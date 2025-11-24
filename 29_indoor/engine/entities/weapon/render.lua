-- entities/weapon/render.lua
-- Rendering: weapon sprite, slash effects, particles, debug visualization

local render = {}
local text_ui = require "engine.utils.text"

function render.createSheathParticleSystem(effects_config)
    -- Get config values with fallbacks
    local particle_size = (effects_config and effects_config.particle_size) or 12
    local particle_sizes = (effects_config and effects_config.particle_sizes) or {3, 3.5, 4, 3, 0}
    local speed_min = (effects_config and effects_config.particle_speed_min) or 30
    local speed_max = (effects_config and effects_config.particle_speed_max) or 80

    -- Create particle image (configurable size)
    local particle_data = love.image.newImageData(particle_size, particle_size)
    local half_size = particle_size / 2
    particle_data:mapPixel(function(x, y, r, g, b, a)
        local dx = x - half_size
        local dy = y - half_size
        local dist = math.sqrt(dx * dx + dy * dy)
        local alpha = math.max(0, 1 - dist / half_size)
        return 1, 1, 1, alpha
    end)
    local particle_img = love.graphics.newImage(particle_data)

    -- Create particle system
    local ps = love.graphics.newParticleSystem(particle_img, 150)
    ps:setParticleLifetime(0.4, 0.8)
    ps:setEmissionRate(0)
    ps:setSizes(unpack(particle_sizes))

    -- Gold/yellow fading
    ps:setColors(
        1, 1, 0.7, 1,
        1, 0.9, 0.5, 0.8,
        1, 0.8, 0.3, 0.5,
        0.9, 0.7, 0.2, 0.2,
        0.8, 0.6, 0.1, 0
    )

    ps:setLinearDamping(1, 3)
    ps:setSpeed(speed_min, speed_max)
    ps:setSpread(math.pi * 2)
    ps:setRotation(0, 2 * math.pi)
    ps:setRelativeRotation(false)

    return ps
end

function render.draw(weapon, debug_mode, swing_configs)
    if not weapon.sprite_sheet then
        return
    end

    -- Save current color (set by enemy render for dead/stunned effects)
    local r, g, b, a = love.graphics.getColor()

    -- Draw slash effect (behind weapon) - use current color (only if sprite available)
    if weapon.slash_active and weapon.slash_anim and weapon.slash_sprite then
        weapon.slash_anim:draw(
            weapon.slash_sprite,
            weapon.slash_x,
            weapon.slash_y,
            weapon.slash_rotation,
            weapon.slash_scale * weapon.slash_flip_x,
            weapon.slash_scale * weapon.slash_flip_y,
            weapon.slash_origin_x,
            weapon.slash_origin_y
        )
    end

    -- Determine sprite flip (X-axis flip for direction change)
    local swing_config = swing_configs[weapon.current_direction]
    local scale_x = weapon.config.scale
    local scale_y = weapon.config.scale

    if swing_config and swing_config.flip_x then
        scale_x = -scale_x -- Horizontal flip
    end

    -- Draw weapon sprite - use current color (preserves enemy's dead/stunned color)
    love.graphics.draw(
        weapon.sprite_sheet,
        weapon.sprite_quad,
        weapon.x,
        weapon.y,
        weapon.angle + math.pi / 2,
        scale_x,
        scale_y,
        weapon.config.sprite_w / 2,
        weapon.config.sprite_h / 2
    )

    -- Debug visualization (only when debugging)
    if debug_mode then
        love.graphics.setColor(1, 1, 1, 1)  -- Reset for debug visuals
        render.drawDebug(weapon, swing_configs)
        love.graphics.setColor(r, g, b, a)  -- Restore original color
    end
end

function render.drawDebug(weapon, swing_configs)
    -- Hand position (YELLOW)
    if weapon.debug_hand_x and weapon.debug_hand_y then
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.circle("fill", weapon.debug_hand_x, weapon.debug_hand_y, 8)
        love.graphics.setColor(1, 1, 0, 0.3)
        love.graphics.circle("line", weapon.debug_hand_x, weapon.debug_hand_y, 15)
        text_ui:draw("HAND", weapon.debug_hand_x - 15, weapon.debug_hand_y - 25, {1, 1, 0, 1})
    end

    -- Weapon center (GREEN)
    love.graphics.setColor(0, 1, 0, 1)
    love.graphics.circle("fill", weapon.x, weapon.y, 6)
    love.graphics.setColor(0, 1, 0, 0.3)
    love.graphics.circle("line", weapon.x, weapon.y, 12)
    text_ui:draw("CENTER", weapon.x - 20, weapon.y + 20, {0, 1, 0, 1})

    -- Weapon handle (CYAN)
    local handle_anchors = require "engine.entities.weapon.config.handle_anchors"
    local handle_anchor = handle_anchors.WEAPON_HANDLE_ANCHORS[weapon.current_direction] or handle_anchors.WEAPON_HANDLE_ANCHORS.right
    local swing_config = swing_configs[weapon.current_direction]

    local handle_x = handle_anchor.x
    local handle_y = handle_anchor.y

    -- X-axis flip: mirror X only
    if swing_config and swing_config.flip_x then
        handle_x = weapon.config.sprite_w - handle_anchor.x
    end

    local handle_offset_x = (handle_x - weapon.config.sprite_w / 2)
    local handle_offset_y = (handle_y - weapon.config.sprite_h / 2)
    local actual_angle = weapon.angle + math.pi / 2
    local cos_angle = math.cos(actual_angle)
    local sin_angle = math.sin(actual_angle)
    local rotated_offset_x = handle_offset_x * cos_angle - handle_offset_y * sin_angle
    local rotated_offset_y = handle_offset_x * sin_angle + handle_offset_y * cos_angle
    local handle_world_x = weapon.x + (rotated_offset_x * weapon.config.scale)
    local handle_world_y = weapon.y + (rotated_offset_y * weapon.config.scale)

    love.graphics.setColor(0, 1, 1, 1)
    love.graphics.circle("fill", handle_world_x, handle_world_y, 10)
    love.graphics.setColor(0, 1, 1, 0.5)
    love.graphics.circle("line", handle_world_x, handle_world_y, 18)
    text_ui:draw("HANDLE", handle_world_x - 22, handle_world_y - 30, {0, 1, 1, 1})

    -- Line connecting hand to handle
    if weapon.debug_hand_x and weapon.debug_hand_y then
        love.graphics.setColor(1, 0, 1, 0.9)
        love.graphics.setLineWidth(3)
        love.graphics.line(weapon.debug_hand_x, weapon.debug_hand_y, handle_world_x, handle_world_y)
        love.graphics.setLineWidth(1)
    end

    -- Slash effect debug (ORANGE)
    if weapon.slash_active then
        love.graphics.setColor(1, 0.5, 0, 1)
        love.graphics.circle("fill", weapon.slash_x, weapon.slash_y, 8)
        love.graphics.setColor(1, 0.5, 0, 0.5)
        love.graphics.circle("line", weapon.slash_x, weapon.slash_y, 35)
        text_ui:draw("SLASH", weapon.slash_x - 20, weapon.slash_y - 45, {1, 0.5, 0, 1})
    end

    -- Attack hitbox
    if weapon.is_attacking then
        local combat = require "engine.entities.weapon.combat"
        local hitbox = combat.getHitbox(weapon)
        if hitbox and combat.canDealDamage(weapon) then
            love.graphics.setColor(1, 0, 0, 0.3)
            love.graphics.circle("fill", hitbox.x, hitbox.y, hitbox.radius)
            love.graphics.setColor(1, 0, 0, 0.8)
            love.graphics.circle("line", hitbox.x, hitbox.y, hitbox.radius)
        end
    end
end

function render.drawSheathParticles(weapon)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(weapon.sheath_particles, weapon.owner_x, weapon.owner_y)
    love.graphics.setColor(1, 1, 1, 1)
end

return render

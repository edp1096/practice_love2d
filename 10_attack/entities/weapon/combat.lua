-- entities/weapon/combat.lua
-- Combat logic: attack, hit detection, damage with effects integration

local effects = require "systems.effects"

local combat = {}

function combat.startAttack(weapon)
    if weapon.is_attacking then
        return false
    end

    weapon.is_attacking = true
    weapon.attack_progress = 0
    weapon.has_hit = false
    weapon.hit_enemies = {}

    -- Create slash effect animation
    local anim8 = require "vendor.anim8"
    weapon.slash_active = true
    weapon.slash_anim = anim8.newAnimation(
        weapon.slash_grid('1-2', 1),
        0.06,
        function() weapon.slash_active = false end
    )

    -- Position slash effect
    local dir_x = math.cos(weapon.angle)
    local dir_y = math.sin(weapon.angle)

    weapon.slash_x = weapon.owner_x + dir_x * 33
    weapon.slash_y = weapon.owner_y + dir_y * 33 + 3
    weapon.slash_rotation = math.atan2(dir_y, dir_x)

    -- Flip Y based on direction
    if weapon.current_direction == "left" or weapon.current_direction == "up" then
        weapon.slash_flip_y = -1
    else
        weapon.slash_flip_y = 1
    end

    -- Spawn weapon trail effect
    local trail_x = weapon.owner_x + dir_x * 40
    local trail_y = weapon.owner_y + dir_y * 40
    effects:spawnWeaponTrail(trail_x, trail_y, weapon.angle)

    return true
end

function combat.endAttack(weapon)
    weapon.is_attacking = false
    weapon.attack_progress = 0
    weapon.current_swing_angle = 0
    weapon.has_hit = false
    weapon.hit_enemies = {}
    weapon.slash_active = false
    weapon.slash_anim = nil
end

function combat.canDealDamage(weapon)
    if not weapon.is_attacking then
        return false
    end

    return weapon.attack_progress >= weapon.config.hit_start and
        weapon.attack_progress <= weapon.config.hit_end
end

function combat.getHitbox(weapon)
    if not combat.canDealDamage(weapon) then
        return nil
    end

    return {
        x = weapon.x,
        y = weapon.y,
        radius = weapon.config.range
    }
end

function combat.checkHit(weapon, enemy)
    if weapon.hit_enemies[enemy] then
        return false
    end

    if not combat.canDealDamage(weapon) then
        return false
    end

    local hitbox = combat.getHitbox(weapon)
    if not hitbox then
        return false
    end

    local enemy_x = enemy.x + enemy.collider_offset_x
    local enemy_y = enemy.y + enemy.collider_offset_y

    local dx = enemy_x - hitbox.x
    local dy = enemy_y - hitbox.y
    local distance = math.sqrt(dx * dx + dy * dy)

    if distance < hitbox.radius + enemy.collider_width / 2 then
        weapon.hit_enemies[enemy] = true
        return true
    end

    return false
end

function combat.getDamage(weapon)
    return weapon.config.damage
end

function combat.getKnockback(weapon)
    return weapon.config.knockback
end

return combat

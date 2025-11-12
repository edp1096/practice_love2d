-- entities/player/combat.lua
-- Combat system: attack, parry, dodge, damage with effects integration, haptic feedback, and sound

local weapon_class = require "engine.entities.weapon"
local effects = require "engine.systems.effects"
local input = require "engine.core.input"
local player_sound = require "engine.entities.player.sound"
local constants = require "engine.core.constants"

local combat = {}

function combat.initialize(player, cfg)
    cfg = cfg or {}

    -- player.weapon = weapon_class:new("sword")
    player.weapon = weapon_class:new("axe")
    player.state = "idle"
    player.attack_cooldown = 0
    player.attack_cooldown_max = cfg.attack_cooldown or 0.5

    player.weapon_drawn = false
    player.last_action_time = 0
    player.weapon_sheath_delay = cfg.weapon_sheath_delay or 5.0

    player.max_health = cfg.max_health or 100
    player.health = player.max_health

    player.hit_flash_timer = 0
    player.hit_shake_x = 0
    player.hit_shake_y = 0
    player.hit_shake_intensity = cfg.hit_shake_intensity or 6
    player.invincible_timer = 0
    player.invincible_duration = cfg.invincible_duration or 1.0

    player.parry_active = false
    player.parry_window = cfg.parry_window or 0.4
    player.parry_perfect_window = cfg.parry_perfect_window or 0.2
    player.parry_timer = 0
    player.parry_cooldown = 0
    player.parry_cooldown_duration = cfg.parry_cooldown or 1.0
    player.parry_success = false
    player.parry_success_timer = 0
    player.parry_perfect = false

    player.dodge_active = false
    player.dodge_duration = cfg.dodge_duration or 0.3
    player.dodge_timer = 0
    player.dodge_cooldown = 0
    player.dodge_cooldown_duration = cfg.dodge_cooldown or 1.0
    player.dodge_distance = cfg.dodge_distance or 150
    player.dodge_speed = 0
    player.dodge_direction_x = 0
    player.dodge_direction_y = 0
    player.dodge_invincible_duration = cfg.dodge_invincible_duration or 0.25
    player.dodge_invincible_timer = 0

    -- Initialize player sounds
    player_sound.initialize()
end

function combat.updateTimers(player, dt)
    if player.attack_cooldown > 0 then
        player.attack_cooldown = player.attack_cooldown - dt
    end

    if player.parry_cooldown > 0 then
        player.parry_cooldown = player.parry_cooldown - dt
    end

    if player.dodge_cooldown > 0 then
        player.dodge_cooldown = player.dodge_cooldown - dt
    end

    if player.dodge_active then
        player.dodge_timer = player.dodge_timer - dt
        if player.dodge_timer <= 0 then
            player.dodge_active = false
            player.state = "idle"
            player.dodge_speed = 0
            -- Change back to Player collision class
            if player.collider then
                player.collider:setCollisionClass(constants.COLLISION_CLASSES.PLAYER)
            end
        end
    end

    if player.dodge_invincible_timer > 0 then
        player.dodge_invincible_timer = player.dodge_invincible_timer - dt
    end

    if player.parry_active then
        player.parry_timer = player.parry_timer - dt
        if player.parry_timer <= 0 then
            player.parry_active = false
            player.state = "idle"
            player.parry_cooldown = player.parry_cooldown_duration
        end
    end

    if player.parry_success_timer > 0 then
        player.parry_success_timer = player.parry_success_timer - dt
        if player.parry_success_timer <= 0 then
            player.parry_success = false
            player.parry_perfect = false
        end
    end

    if player.hit_flash_timer > 0 then
        player.hit_flash_timer = math.max(0, player.hit_flash_timer - dt)
    end

    if player.invincible_timer > 0 then
        player.invincible_timer = math.max(0, player.invincible_timer - dt)
    end

    if player.hit_flash_timer > 0 then
        player.hit_shake_x = (math.random() - 0.5) * 2 * player.hit_shake_intensity
        player.hit_shake_y = (math.random() - 0.5) * 2 * player.hit_shake_intensity
    else
        player.hit_shake_x = 0
        player.hit_shake_y = 0
    end

    if player.weapon_drawn and player.state ~= "attacking" and not player.parry_active then
        player.last_action_time = player.last_action_time + dt
        if player.last_action_time >= player.weapon_sheath_delay then
            player.weapon_drawn = false
            player.weapon:emitSheathParticles()
            -- Reset aim source when weapon is sheathed
            input:resetAimSource()

            -- Play weapon sheath sound
            player_sound.playWeaponSheath()
        end
    end

    -- Update player sound system
    player_sound.update(dt, player)
end

function combat.attack(player)
    if player.parry_active or player.parry_cooldown > 0 then
        return false
    end

    if player.state == "attacking" then
        return false
    end

    if player.attack_cooldown > 0 then
        return false
    end

    if not player.weapon_drawn then
        player.weapon_drawn = true
        -- Initialize aim direction to current facing direction when drawing weapon
        input:setAimAngle(player.facing_angle, "initial")

        -- Play weapon draw sound
        player_sound.playWeaponDraw()
    end

    player.last_action_time = 0

    if player.weapon:startAttack() then
        player.state = "attacking"
        player.attack_cooldown = player.attack_cooldown_max

        -- Haptic feedback for attack
        local v = constants.VIBRATION.ATTACK; input:vibrate(v.duration, v.left, v.right)

        -- Play attack sound
        player_sound.playAttack()

        return true
    end

    return false
end

function combat.startParry(player)
    if player.parry_cooldown > 0 or player.state == "attacking" or player.parry_active or player.dodge_active then
        return false
    end

    if not player.weapon_drawn then
        player.weapon_drawn = true
        -- Initialize aim direction to current facing direction when drawing weapon
        input:setAimAngle(player.facing_angle, "initial")

        -- Play weapon draw sound
        player_sound.playWeaponDraw()
    end

    player.last_action_time = 0
    player.parry_active = true
    player.parry_timer = player.parry_window
    player.state = "parrying"

    return true
end

function combat.startDodge(player)
    if player.dodge_cooldown > 0 or player.state == "attacking" or player.parry_active or player.dodge_active then
        return false
    end

    -- Get dodge direction from input system (supports gamepad)
    local dir_x, dir_y = input:getMovement()

    -- Platformer mode: only horizontal dodge
    if player.game_mode == "platformer" then
        dir_y = 0
    end

    if dir_x == 0 and dir_y == 0 then
        -- Use current facing direction if no input
        if player.direction == "right" then
            dir_x = 1
        elseif player.direction == "left" then
            dir_x = -1
        elseif player.direction == "down" then
            dir_y = 1
        elseif player.direction == "up" then
            dir_y = -1
        end
    end

    local length = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    if length > 0 then
        dir_x = dir_x / length
        dir_y = dir_y / length
    end

    -- Platformer mode: always horizontal direction
    if player.game_mode == "platformer" then
        player.direction = dir_x >= 0 and "right" or "left"
    else
        if math.abs(dir_x) > math.abs(dir_y) then
            player.direction = dir_x > 0 and "right" or "left"
        else
            player.direction = dir_y > 0 and "down" or "up"
        end
    end

    player.dodge_active = true
    player.dodge_timer = player.dodge_duration
    player.dodge_speed = player.dodge_distance / player.dodge_duration
    player.dodge_direction_x = dir_x
    player.dodge_direction_y = dir_y
    player.dodge_cooldown = player.dodge_cooldown_duration
    player.dodge_invincible_timer = player.dodge_invincible_duration
    player.state = "dodging"

    -- Change collision class to PlayerDodging (ignores Enemy, collides with Wall)
    if player.collider then
        player.collider:setCollisionClass(constants.COLLISION_CLASSES.PLAYER_DODGING)
    end

    player.last_action_time = 0

    -- Haptic feedback for dodge
    local v = constants.VIBRATION.DODGE; input:vibrate(v.duration, v.left, v.right)

    -- Play dodge sound
    player_sound.playDodge()

    return true
end

function combat.checkParry(player, incoming_damage)
    if not player.parry_active then
        return false, false
    end

    local time_elapsed = player.parry_window - player.parry_timer
    local is_perfect = time_elapsed <= player.parry_perfect_window

    player.parry_active = false
    player.parry_timer = 0  -- Reset timer to prevent cooldown application
    player.parry_success = true
    player.parry_perfect = is_perfect
    player.parry_success_timer = 0.5
    player.parry_cooldown = 0
    player.state = "idle"

    effects:spawnParryEffect(player.x, player.y, player.facing_angle, is_perfect)

    -- Haptic feedback for parry
    if is_perfect then
        local v = constants.VIBRATION.PERFECT_PARRY; input:vibrate(v.duration, v.left, v.right)
    else
        local v = constants.VIBRATION.PARRY; input:vibrate(v.duration, v.left, v.right)
    end

    -- Play parry sound
    player_sound.playParry(is_perfect)

    return true, is_perfect
end

function combat.takeDamage(player, damage, shake_callback)
    local parried, is_perfect = combat.checkParry(player, damage)
    if parried then
        if shake_callback then
            shake_callback(4, 0.1)
        end
        return false, true, is_perfect
    end

    if player.dodge_invincible_timer > 0 then
        return false, false, false
    end

    if player.invincible_timer > 0 then
        return false, false, false
    end

    player.health = math.max(0, player.health - damage)

    effects:spawnHitEffect(player.x, player.y, "player", nil)

    player.hit_flash_timer = 0.2
    player.invincible_timer = player.invincible_duration
    player.parry_cooldown = 0 -- reset parry cooldown when taking damage

    -- Haptic feedback for hit
    local v = constants.VIBRATION.HIT; input:vibrate(v.duration, v.left, v.right)

    -- Play hurt sound
    player_sound.playHurt()

    if shake_callback then
        shake_callback(12, 0.3)
    end

    return true, false, false
end

function combat.isAlive(player)
    return player.health > 0
end

function combat.isInvincible(player)
    return player.invincible_timer > 0
end

function combat.isParrying(player)
    return player.parry_active
end

function combat.isDodging(player)
    return player.dodge_active
end

function combat.isDodgeInvincible(player)
    return player.dodge_invincible_timer > 0
end

return combat

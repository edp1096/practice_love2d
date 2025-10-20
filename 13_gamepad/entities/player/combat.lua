-- entities/player/combat.lua
-- Combat system: attack, parry, dodge, damage with effects integration

local weapon_class = require "entities.weapon"
local effects = require "systems.effects"

local combat = {}

function combat.initialize(player)
    player.weapon = weapon_class:new("sword")
    player.state = "idle"
    player.attack_cooldown = 0
    player.attack_cooldown_max = 0.5

    player.weapon_drawn = false
    player.last_action_time = 0
    player.weapon_sheath_delay = 5.0

    player.max_health = 100
    player.health = player.max_health

    player.hit_flash_timer = 0
    player.hit_shake_x = 0
    player.hit_shake_y = 0
    player.hit_shake_intensity = 6
    player.invincible_timer = 0
    player.invincible_duration = 1.0

    player.parry_active = false
    player.parry_window = 0.4
    player.parry_perfect_window = 0.2
    player.parry_timer = 0
    player.parry_cooldown = 0
    player.parry_cooldown_duration = 1.0
    player.parry_success = false
    player.parry_success_timer = 0
    player.parry_perfect = false

    player.dodge_active = false
    player.dodge_duration = 0.3
    player.dodge_timer = 0
    player.dodge_cooldown = 0
    player.dodge_cooldown_duration = 1.0
    player.dodge_distance = 150
    player.dodge_speed = 0
    player.dodge_direction_x = 0
    player.dodge_direction_y = 0
    player.dodge_invincible_duration = 0.25
    player.dodge_invincible_timer = 0
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
                player.collider:setCollisionClass("Player")
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
        end
    end
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
    end

    player.last_action_time = 0

    if player.weapon:startAttack() then
        player.state = "attacking"
        player.attack_cooldown = player.attack_cooldown_max
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

    local dir_x, dir_y = 0, 0

    if love.keyboard.isDown("right", "d") then dir_x = 1 end
    if love.keyboard.isDown("left", "a") then dir_x = -1 end
    if love.keyboard.isDown("down", "s") then dir_y = 1 end
    if love.keyboard.isDown("up", "w") then dir_y = -1 end

    if dir_x == 0 and dir_y == 0 then
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

    if math.abs(dir_x) > math.abs(dir_y) then
        player.direction = dir_x > 0 and "right" or "left"
    else
        player.direction = dir_y > 0 and "down" or "up"
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
        player.collider:setCollisionClass("PlayerDodging")
    end

    player.last_action_time = 0

    return true
end

function combat.checkParry(player, incoming_damage)
    if not player.parry_active then
        return false, false
    end

    local time_elapsed = player.parry_window - player.parry_timer
    local is_perfect = time_elapsed <= player.parry_perfect_window

    player.parry_active = false
    player.parry_success = true
    player.parry_perfect = is_perfect
    player.parry_success_timer = 0.5
    player.parry_cooldown = 0
    player.state = "idle"

    effects:spawnParryEffect(player.x, player.y, player.facing_angle, is_perfect)

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
        print("Dodged attack!")
        return false, false, false
    end

    if player.invincible_timer > 0 then
        return false, false, false
    end

    player.health = math.max(0, player.health - damage)

    effects:spawnHitEffect(player.x, player.y, "player", nil)

    player.hit_flash_timer = 0.2
    player.invincible_timer = player.invincible_duration

    if shake_callback then
        shake_callback(12, 0.3)
    end

    if player.health <= 0 then
        print("Player died!")
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

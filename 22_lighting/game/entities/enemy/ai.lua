-- entities/enemy/ai.lua
-- AI state machine: idle, patrol, chase, attack, hit with sound integration

local enemy_sound = require "game.entities.enemy.sound"

local ai = {}

function ai.update(enemy, dt, player_x, player_y)
    -- State machine
    if enemy.state == "idle" then
        ai.updateIdle(enemy, dt, player_x, player_y)
    elseif enemy.state == "patrol" then
        ai.updatePatrol(enemy, dt, player_x, player_y)
    elseif enemy.state == "chase" then
        ai.updateChase(enemy, dt, player_x, player_y)
    elseif enemy.state == "attack_windup" then
        ai.updateAttackWindup(enemy, dt, player_x, player_y)
    elseif enemy.state == "attack" then
        ai.updateAttack(enemy, dt, player_x, player_y)
    elseif enemy.state == "hit" then
        ai.updateHit(enemy, dt)
    elseif enemy.state == "dead" then
        return 0, 0
    end

    -- Calculate movement
    local vx, vy = 0, 0
    if (enemy.state == "patrol" or enemy.state == "chase") and enemy.target_x and enemy.target_y then
        -- Check if we're in platformer mode
        local is_platformer = enemy.world and enemy.world.game_mode == "platformer"

        local dx = enemy.target_x - enemy.x
        local dy = is_platformer and 0 or (enemy.target_y - enemy.y) -- Ignore Y in platformer mode
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > 5 then
            vx = (dx / distance) * enemy.speed
            vy = is_platformer and 0 or ((dy / distance) * enemy.speed) -- No Y movement in platformer

            -- Update direction based on movement vector
            if enemy.is_humanoid then
                -- 4-direction movement for humanoid (topdown) or 2-direction (platformer)
                local abs_dx = math.abs(dx)
                local abs_dy = math.abs(dy)

                if is_platformer or abs_dx > abs_dy then
                    -- In platformer mode, always use left/right
                    if dx > 0 then
                        enemy.direction = "right"
                    else
                        enemy.direction = "left"
                    end
                else
                    -- In topdown mode, can use up/down
                    if dy > 0 then
                        enemy.direction = "down"
                    else
                        enemy.direction = "up"
                    end
                end
            else
                -- 2-direction movement for slime
                if math.abs(dx) > 5 then
                    if dx > 0 then
                        enemy.direction = "right"
                    else
                        enemy.direction = "left"
                    end
                end
            end
        end
    end

    return vx, vy
end

function ai.updateIdle(enemy, dt, player_x, player_y)
    enemy.anim = enemy.animations["idle_" .. enemy.direction]

    -- Check for player detection
    local is_platformer = enemy.world and enemy.world.game_mode == "platformer"
    local distance
    if is_platformer then
        -- Platformer: only horizontal distance
        local dx = player_x - (enemy.x + enemy.collider_offset_x)
        distance = math.abs(dx)
    else
        distance = enemy:getDistanceToPoint(player_x, player_y)
    end

    if distance < enemy.detection_range then
        local collider_center_x = enemy.x + enemy.collider_offset_x
        local collider_center_y = enemy.y + enemy.collider_offset_y
        if enemy.world and enemy.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
            ai.setState(enemy, "chase")

            -- Play detection sound
            enemy_sound.playDetect()
        end
    end

    -- Transition to patrol after timer
    if enemy.state_timer <= 0 then
        if #enemy.patrol_points > 0 then
            ai.setState(enemy, "patrol")
        else
            enemy.state_timer = math.random(2, 5)
        end
    end
end

function ai.updatePatrol(enemy, dt, player_x, player_y)
    enemy.anim = enemy.animations["walk_" .. enemy.direction]

    -- Check for player detection
    local is_platformer = enemy.world and enemy.world.game_mode == "platformer"
    local distance
    if is_platformer then
        -- Platformer: only horizontal distance
        local dx = player_x - (enemy.x + enemy.collider_offset_x)
        distance = math.abs(dx)
    else
        distance = enemy:getDistanceToPoint(player_x, player_y)
    end

    if distance < enemy.detection_range then
        local collider_center_x = enemy.x + enemy.collider_offset_x
        local collider_center_y = enemy.y + enemy.collider_offset_y
        if enemy.world and enemy.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
            ai.setState(enemy, "chase")

            -- Play detection sound
            enemy_sound.playDetect()
            return
        end
    end

    -- Follow patrol points
    if #enemy.patrol_points > 0 then
        local is_platformer = enemy.world and enemy.world.game_mode == "platformer"
        local patrol_point = enemy.patrol_points[enemy.current_patrol_index]
        enemy.target_x = patrol_point.x
        enemy.target_y = is_platformer and enemy.y or patrol_point.y -- Keep current Y in platformer mode

        local dist_to_point = enemy:getDistanceToPoint(enemy.target_x, enemy.target_y)
        if dist_to_point < 10 then
            enemy.current_patrol_index = enemy.current_patrol_index + 1
            if enemy.current_patrol_index > #enemy.patrol_points then
                enemy.current_patrol_index = 1
            end
            ai.setState(enemy, "idle")
        end
    end
end

function ai.updateChase(enemy, dt, player_x, player_y)
    enemy.anim = enemy.animations["walk_" .. enemy.direction]

    -- Check if platformer mode
    local is_platformer = enemy.world and enemy.world.game_mode == "platformer"

    -- In platformer mode, only check horizontal distance
    local distance
    if is_platformer then
        local dx = player_x - (enemy.x + enemy.collider_offset_x)
        distance = math.abs(dx)
    else
        distance = enemy:getDistanceToPoint(player_x, player_y)
    end

    -- Calculate edge-to-edge distance for attack range check
    local effective_attack_range = enemy.attack_range

    if enemy.is_humanoid then
        local dx = player_x - (enemy.x + enemy.collider_offset_x)
        local dy = player_y - (enemy.y + enemy.collider_offset_y)
        local abs_dx = math.abs(dx)
        local abs_dy = math.abs(dy)

        -- Calculate edge-to-edge distance by subtracting collider radii
        local edge_distance = distance
        if is_platformer then
            -- Platformer: horizontal only, subtract width radii
            edge_distance = distance - 45
        elseif abs_dy > abs_dx then
            -- Topdown vertical: subtract height radii (enemy: 40, player: ~50)
            edge_distance = distance - 90
        else
            -- Topdown horizontal: subtract width radii (enemy: 20, player: ~25)
            edge_distance = distance - 45
        end

        -- Check edge-to-edge distance instead of center-to-center
        if edge_distance < effective_attack_range then
            ai.setState(enemy, "attack_windup")
            return
        end
    else
        -- Slime uses simple distance check
        -- In platformer, subtract collider widths
        local attack_distance = distance
        if is_platformer then
            attack_distance = distance - 40  -- Subtract approximate widths (slime + player)
        end

        if attack_distance < effective_attack_range then
            ai.setState(enemy, "attack_windup")
            return
        end
    end

    -- Lost player (too far)
    if distance > enemy.detection_range * 1.5 then
        ai.setState(enemy, "idle")
        return
    end

    -- Lost line of sight
    local collider_center_x = enemy.x + enemy.collider_offset_x
    local collider_center_y = enemy.y + enemy.collider_offset_y
    if enemy.world and not enemy.world:checkLineOfSight(collider_center_x, collider_center_y, player_x, player_y) then
        ai.setState(enemy, "idle")
        return
    end

    -- Chase player
    local is_platformer = enemy.world and enemy.world.game_mode == "platformer"
    enemy.target_x = player_x
    enemy.target_y = is_platformer and enemy.y or player_y -- Keep current Y in platformer mode
end

function ai.updateAttackWindup(enemy, dt, player_x, player_y)
    -- Windup phase - enemy prepares to attack
    -- Update direction to face player during windup
    if enemy.is_humanoid then
        local dx = player_x - enemy.x
        local dy = player_y - enemy.y
        local abs_dx = math.abs(dx)
        local abs_dy = math.abs(dy)

        if abs_dx > abs_dy then
            if dx > 0 then
                enemy.direction = "right"
            else
                enemy.direction = "left"
            end
        else
            if dy > 0 then
                enemy.direction = "down"
            else
                enemy.direction = "up"
            end
        end
    end

    -- Use idle animation during windup (could use a specific windup animation if available)
    enemy.anim = enemy.animations["idle_" .. enemy.direction]

    -- Transition to actual attack after windup time
    if enemy.state_timer <= 0 then
        ai.setState(enemy, "attack")
    end
end

function ai.updateAttack(enemy, dt, player_x, player_y)
    -- Update direction to face player during attack (for humanoid)
    if enemy.is_humanoid then
        local dx = player_x - enemy.x
        local dy = player_y - enemy.y
        local abs_dx = math.abs(dx)
        local abs_dy = math.abs(dy)

        if abs_dx > abs_dy then
            if dx > 0 then
                enemy.direction = "right"
            else
                enemy.direction = "left"
            end
        else
            if dy > 0 then
                enemy.direction = "down"
            else
                enemy.direction = "up"
            end
        end
    end

    enemy.anim = enemy.animations["attack_" .. enemy.direction]

    if enemy.attack_timer <= 0 then
        enemy.attack_timer = enemy.attack_cooldown

        -- Play attack sound
        if not enemy.has_attacked then
            enemy_sound.playAttack(enemy.type)
            enemy.has_attacked = true
        end
    end

    if enemy.state_timer <= 0 then
        ai.setState(enemy, "chase")
    end
end

function ai.updateHit(enemy, dt)
    if enemy.state_timer <= 0 then
        if enemy.health > 0 then
            ai.setState(enemy, "chase")
        else
            ai.setState(enemy, "dead")
        end
    end
end

function ai.setState(enemy, new_state)
    enemy.state = new_state

    if new_state == "idle" then
        enemy.state_timer = math.random(1, 3)
    elseif new_state == "attack_windup" then
        enemy.state_timer = 0.15  -- Windup duration (telegraph)
    elseif new_state == "attack" then
        enemy.state_timer = 0.5
        enemy.has_attacked = false
    elseif new_state == "hit" then
        enemy.state_timer = 0.3
        enemy.hit_flash_timer = 0.15
    end
end

return ai

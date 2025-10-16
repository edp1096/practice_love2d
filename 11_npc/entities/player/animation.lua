-- entities/player/animation.lua
-- Animation control and direction management

local anim8 = require "vendor.anim8"
local debug = require "systems.debug"

local animation = {}

function animation.initialize(player, sprite_sheet)
    player.spriteSheet = love.graphics.newImage(sprite_sheet)
    player.grid = anim8.newGrid(48, 48, player.spriteSheet:getWidth(), player.spriteSheet:getHeight())

    player.animations = {}
    player.animations.walk_up = anim8.newAnimation(player.grid("1-4", 4), 0.1)
    player.animations.walk_down = anim8.newAnimation(player.grid("1-4", 3), 0.1)
    player.animations.walk_left = anim8.newAnimation(player.grid("5-8", 4, "1-2", 5), 0.1)
    player.animations.walk_right = anim8.newAnimation(player.grid("3-8", 5), 0.1)

    player.animations.idle_up = anim8.newAnimation(player.grid("5-8", 1), 0.15)
    player.animations.idle_down = anim8.newAnimation(player.grid("1-4", 1), 0.15)
    player.animations.idle_left = anim8.newAnimation(player.grid("1-4", 2), 0.15)
    player.animations.idle_right = anim8.newAnimation(player.grid("5-8", 2), 0.15)

    player.animations.attack_down = anim8.newAnimation(player.grid("1-4", 11), 0.08)
    player.animations.attack_up = anim8.newAnimation(player.grid("5-8", 11), 0.08)
    player.animations.attack_left = anim8.newAnimation(player.grid("1-4", 12), 0.08)
    player.animations.attack_right = anim8.newAnimation(player.grid("5-8", 12), 0.08)

    player.anim = player.animations.idle_right
    player.direction = "right"
    player.facing_angle = 0
    player.current_anim_name = "idle_right"
end

function animation.update(player, dt, cam)
    local current_anim_name = nil
    local current_frame_index = 1

    -- Direction control
    if debug:IsHandMarkingActive() then
        -- Hand marking mode: WASD controls direction
        if love.keyboard.isDown('w') then
            player.direction = 'up'
            player.facing_angle = -math.pi / 2
        elseif love.keyboard.isDown('s') then
            player.direction = 'down'
            player.facing_angle = math.pi / 2
        elseif love.keyboard.isDown('a') then
            player.direction = 'left'
            player.facing_angle = math.pi
        elseif love.keyboard.isDown('d') then
            player.direction = 'right'
            player.facing_angle = 0
        end
    elseif player.weapon_drawn or player.parry_active then
        -- Mouse aim
        local mouse_x, mouse_y
        if cam then
            mouse_x, mouse_y = cam:worldCoords(love.mouse.getPosition())
        else
            mouse_x, mouse_y = love.mouse.getPosition()
        end

        local raw_angle = math.atan2(mouse_y - player.y, mouse_x - player.x)

        if raw_angle > -math.pi / 4 and raw_angle <= math.pi / 4 then
            player.direction = "right"
            player.facing_angle = 0
        elseif raw_angle > math.pi / 4 and raw_angle <= 3 * math.pi / 4 then
            player.direction = "down"
            player.facing_angle = math.pi / 2
        elseif raw_angle > 3 * math.pi / 4 or raw_angle <= -3 * math.pi / 4 then
            player.direction = "left"
            player.facing_angle = math.pi
        else
            player.direction = "up"
            player.facing_angle = -math.pi / 2
        end
    end

    -- Check if attack animation finished
    if player.state == "attacking" and not player.weapon.is_attacking then
        player.state = "idle"
    end

    local vx, vy = 0, 0
    local is_moving = false
    local movement_input = false

    if love.keyboard.isDown("right", "d") or
        love.keyboard.isDown("left", "a") or
        love.keyboard.isDown("down", "s") or
        love.keyboard.isDown("up", "w") then
        movement_input = true
    end

    -- Determine animation
    if player.state ~= "attacking" and not player.parry_active and not player.dodge_active and not debug:IsHandMarkingActive() then
        local move_direction = nil

        if love.keyboard.isDown("right", "d") then
            vx = player.speed
            is_moving = true
            move_direction = "right"
        end
        if love.keyboard.isDown("left", "a") then
            vx = -player.speed
            is_moving = true
            move_direction = "left"
        end
        if love.keyboard.isDown("down", "s") then
            vy = player.speed
            is_moving = true
            move_direction = "down"
        end
        if love.keyboard.isDown("up", "w") then
            vy = -player.speed
            is_moving = true
            move_direction = "up"
        end

        if not player.weapon_drawn and move_direction then
            player.direction = move_direction
            if player.direction == "right" then
                player.facing_angle = 0
            elseif player.direction == "left" then
                player.facing_angle = math.pi
            elseif player.direction == "down" then
                player.facing_angle = math.pi / 2
            elseif player.direction == "up" then
                player.facing_angle = -math.pi / 2
            end
        end

        if is_moving then
            current_anim_name = "walk_" .. player.direction
            player.anim = player.animations[current_anim_name]
            player.anim:update(dt)
            player.state = "walking"
        else
            current_anim_name = "idle_" .. player.direction
            player.anim = player.animations[current_anim_name]
            player.anim:update(dt)
            if player.state ~= "attacking" and not player.parry_active then
                player.state = "idle"
            end
        end
    elseif player.dodge_active then
        vx = player.dodge_direction_x * player.dodge_speed
        vy = player.dodge_direction_y * player.dodge_speed
        current_anim_name = "walk_" .. player.direction
        player.anim = player.animations[current_anim_name]
        player.anim:update(dt * 2)
    elseif player.state == "attacking" then
        current_anim_name = "attack_" .. player.direction
        player.anim = player.animations[current_anim_name]
        if not debug:IsHandMarkingActive() then
            player.anim:update(dt)
        end
    elseif player.parry_active then
        current_anim_name = "idle_" .. player.direction
        player.anim = player.animations[current_anim_name]
        player.anim:update(dt)
    elseif debug:IsHandMarkingActive() then
        -- Hand marking mode
        if movement_input then
            player.state = "walking"
            current_anim_name = "walk_" .. player.direction
        elseif player.state == "attacking" then
            current_anim_name = "attack_" .. player.direction
        else
            if player.state ~= "attacking" and not player.parry_active then
                player.state = "idle"
            end
            current_anim_name = "idle_" .. player.direction
        end

        if not player.anim or player.anim ~= player.animations[current_anim_name] then
            player.anim = player.animations[current_anim_name]
        end
    else
        -- Fallback: always ensure current_anim_name is set
        current_anim_name = "idle_" .. player.direction
    end

    -- Always set current_anim_name (never nil)
    player.current_anim_name = current_anim_name or ("idle_" .. player.direction)

    if debug:IsHandMarkingActive() then
        current_frame_index = debug.manual_frame
    elseif player.anim and player.anim.position then
        current_frame_index = math.floor(player.anim.position)
    end

    -- Update weapon
    if player.weapon then
        player.weapon:update(dt, player.x, player.y, player.facing_angle,
            player.direction, player.current_anim_name, current_frame_index, debug:IsHandMarkingActive())
    end

    return vx, vy
end

return animation

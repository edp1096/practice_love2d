-- entities/player/animation.lua
-- Animation control and direction management with gamepad support

local anim8 = require "vendor.anim8"
local debug = require "engine.core.debug"
local input = require "engine.core.input"

local animation = {}

-- Helper: Get weapon position with jump offset applied
local function getWeaponPosition(player)
    local weapon_x = player.x
    local weapon_y = player.y

    -- Apply topdown jump offset for weapon positioning
    if player.game_mode == "topdown" and player.topdown_is_jumping then
        weapon_y = weapon_y + player.topdown_jump_height
    end

    return weapon_x, weapon_y
end

-- Helper: Handle dialogue state (returns early with 0,0 velocity)
local function handleDialogueState(player, dt, dialogue_open)
    if not dialogue_open then
        return false, 0, 0
    end

    local current_anim_name = "idle_" .. player.direction
    player.anim = player.animations[current_anim_name]
    player.anim:update(dt)
    player.state = "idle"
    player.current_anim_name = current_anim_name

    if player.weapon then
        local current_frame_index = player.anim and math.floor(player.anim.position) or 1
        local weapon_x, weapon_y = getWeaponPosition(player)

        player.weapon:update(dt, weapon_x, weapon_y, player.facing_angle,
            player.direction, player.current_anim_name, current_frame_index, debug:IsHandMarkingActive())
    end

    return true, 0, 0
end

-- Helper: Determine facing direction from input/weapon state
local function handleDirectionFromInput(player, cam)
    if debug:IsHandMarkingActive() then
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
        -- Use aim direction from input system (gamepad right stick or mouse)
        local raw_angle = input:getAimDirection(player.x, player.y, cam)

        -- Platformer mode: only horizontal aiming
        if player.game_mode == "platformer" then
            if raw_angle > -math.pi / 2 and raw_angle <= math.pi / 2 then
                player.direction = "right"
                player.facing_angle = 0
            else
                player.direction = "left"
                player.facing_angle = math.pi
            end
        else
            -- Topdown mode: 4-directional aiming
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
    end
end

-- Helper: Process movement input and update animation
local function handleMovementInput(player, dt)
    local vx, vy = 0, 0
    local is_moving = false
    local movement_input = false

    -- Check for movement input (keyboard or gamepad)
    local move_x, move_y = input:getMovement()

    -- In platformer mode, ignore vertical input (W/S keys used for jump/crouch)
    if player.game_mode == "platformer" then
        move_y = 0
    end

    movement_input = (math.abs(move_x) > 0.01 or math.abs(move_y) > 0.01)

    if player.state ~= "attacking" and not player.parry_active and not player.dodge_active and not debug:IsHandMarkingActive() then
        local move_direction = nil

        -- Game mode specific movement
        if player.game_mode == "platformer" then
            -- Platformer mode: horizontal movement only, jump handled separately
            if movement_input then
                vx = move_x * player.speed
                vy = 0 -- Gravity handles vertical movement
                is_moving = math.abs(move_x) > 0.01

                -- Store input direction for jump
                player.last_input_x = move_x

                -- Only left/right direction
                if math.abs(move_x) > 0.01 then
                    move_direction = move_x > 0 and "right" or "left"
                end
            else
                player.last_input_x = 0
            end

            -- Keep current direction if not moving horizontally
            if not move_direction then
                move_direction = player.direction
            end
        else
            -- Topdown mode: 8-directional movement
            if movement_input then
                vx = move_x * player.speed
                vy = move_y * player.speed
                is_moving = true

                -- Determine direction from movement vector
                local abs_x = math.abs(move_x)
                local abs_y = math.abs(move_y)

                if abs_x > abs_y then
                    move_direction = move_x > 0 and "right" or "left"
                else
                    move_direction = move_y > 0 and "down" or "up"
                end
            end
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
            player.anim = player.animations["walk_" .. player.direction]
            player.anim:update(dt)
            player.state = "walking"
        else
            player.anim = player.animations["idle_" .. player.direction]
            player.anim:update(dt)
            if player.state ~= "attacking" and not player.parry_active then
                player.state = "idle"
            end
        end
    end

    return vx, vy, movement_input
end

-- Helper: Handle special states (dodge, attack, parry, debug)
local function handleSpecialStates(player, dt, movement_input)
    local vx, vy = 0, 0

    if player.dodge_active then
        vx = player.dodge_direction_x * player.dodge_speed
        vy = player.dodge_direction_y * player.dodge_speed
        player.anim = player.animations["walk_" .. player.direction]
        player.anim:update(dt * 2)
    elseif player.state == "attacking" then
        player.anim = player.animations["attack_" .. player.direction]
        if not debug:IsHandMarkingActive() then
            player.anim:update(dt)
        end
    elseif player.parry_active then
        player.anim = player.animations["idle_" .. player.direction]
        player.anim:update(dt)
    elseif debug:IsHandMarkingActive() then
        local current_anim_name
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
    end

    return vx, vy
end

-- Helper: Update weapon position and animation
local function handleWeaponUpdate(player, dt, current_frame_index)
    if player.weapon then
        local weapon_x, weapon_y = getWeaponPosition(player)

        player.weapon:update(dt, weapon_x, weapon_y, player.facing_angle,
            player.direction, player.current_anim_name, current_frame_index, debug:IsHandMarkingActive())
    end
end

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

function animation.update(player, dt, cam, dialogue_open)
    dialogue_open = dialogue_open or false

    -- Handle dialogue state (early return if dialogue is open)
    local handled, vx, vy = handleDialogueState(player, dt, dialogue_open)
    if handled then
        return vx, vy
    end

    -- Determine facing direction from input/weapon state
    handleDirectionFromInput(player, cam)

    -- Reset attacking state if weapon finished
    if player.state == "attacking" and player.weapon and not player.weapon.is_attacking then
        player.state = "idle"
    end

    -- Process movement input (or get velocity from special states)
    local movement_input
    vx, vy, movement_input = handleMovementInput(player, dt)

    -- Handle special states (dodge, attack, parry, debug) if not already handled
    if player.dodge_active or player.state == "attacking" or player.parry_active or debug:IsHandMarkingActive() then
        local special_vx, special_vy = handleSpecialStates(player, dt, movement_input)
        if special_vx ~= 0 or special_vy ~= 0 then
            vx, vy = special_vx, special_vy
        end
    end

    -- Set current animation name
    local current_anim_name = "idle_" .. player.direction
    if player.anim then
        for anim_name, anim_obj in pairs(player.animations) do
            if anim_obj == player.anim then
                current_anim_name = anim_name
                break
            end
        end
    end
    player.current_anim_name = current_anim_name

    -- Determine current frame index
    local current_frame_index = 1
    if debug:IsHandMarkingActive() then
        current_frame_index = debug.manual_frame
        if player.anim then
            player.anim:gotoFrame(debug.manual_frame)
        end
    elseif player.anim and player.anim.position then
        current_frame_index = math.floor(player.anim.position)
    end

    -- Update weapon
    handleWeaponUpdate(player, dt, current_frame_index)

    return vx, vy
end

return animation

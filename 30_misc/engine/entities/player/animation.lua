-- entities/player/animation.lua
-- Animation control and direction management with gamepad support

local anim8 = require "vendor.anim8"
local debug = require "engine.core.debug"
local input = require "engine.core.input"

local animation = {}

-- Opposite direction lookup (for backpedaling detection)
local OPPOSITE_DIRS = {
    up = "down", down = "up",
    left = "right", right = "left"
}

-- Check if player is currently jumping (works in both game modes)
local function isJumping(player)
    return (player.game_mode == "topdown" and player.topdown_is_jumping)
        or (player.game_mode == "platformer" and player.is_jumping)
end

-- Check if player is moving opposite to facing direction while weapon drawn
local function isBackpedaling(player, move_direction)
    if player.weapon_drawn and move_direction then
        return OPPOSITE_DIRS[player.direction] == move_direction
    end
    return false
end

-- Get weapon position with jump and stair offset applied
local function getWeaponPosition(player)
    local weapon_x = player.x
    local weapon_y = player.y

    -- Apply topdown jump offset for weapon positioning
    if player.game_mode == "topdown" and player.topdown_is_jumping then
        weapon_y = weapon_y + player.topdown_jump_height
    end

    -- NOTE: Stair movement is now handled by adjusting velocity in moveEntity()
    -- No visual offset needed - the collider actually moves diagonally on stairs

    return weapon_x, weapon_y
end

-- Handle dialogue state (returns early with 0,0 velocity)
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

-- Update facing_angle based on current direction
local function updateFacingAngleFromDirection(player)
    local angles = {
        right = 0,
        left = math.pi,
        down = math.pi / 2,
        up = -math.pi / 2
    }
    player.facing_angle = angles[player.direction] or 0
end

-- Determine facing direction from input/weapon state
local function handleDirectionFromInput(player, cam)
    if debug:IsHandMarkingActive() then
        if love.keyboard.isDown('w') then
            player.direction = 'up'
        elseif love.keyboard.isDown('s') then
            player.direction = 'down'
        elseif love.keyboard.isDown('a') then
            player.direction = 'left'
        elseif love.keyboard.isDown('d') then
            player.direction = 'right'
        end
        updateFacingAngleFromDirection(player)
    elseif player.weapon_drawn or player.parry_active then
        -- Use aim direction from input system (gamepad right stick or mouse)
        local raw_angle = input:getAimDirection(player.x, player.y, cam)

        -- Platformer mode: only horizontal aiming
        if player.game_mode == "platformer" then
            if raw_angle > -math.pi / 2 and raw_angle <= math.pi / 2 then
                player.direction = "right"
            else
                player.direction = "left"
            end
        else
            -- Topdown mode: 4-directional aiming
            if raw_angle > -math.pi / 4 and raw_angle <= math.pi / 4 then
                player.direction = "right"
            elseif raw_angle > math.pi / 4 and raw_angle <= 3 * math.pi / 4 then
                player.direction = "down"
            elseif raw_angle > 3 * math.pi / 4 or raw_angle <= -3 * math.pi / 4 then
                player.direction = "left"
            else
                player.direction = "up"
            end
        end
        updateFacingAngleFromDirection(player)
    else
        -- No weapon: just sync facing_angle with current direction
        updateFacingAngleFromDirection(player)
    end
end

-- Handle riding state (separate idle/move animations with ride effects)
local function handleRidingState(player, dt, move_x, move_y)
    local vx, vy = 0, 0
    local movement_input = math.abs(move_x) > 0.01 or math.abs(move_y) > 0.01

    -- Get ride speed from boarded vehicle
    local ride_speed = player.speed  -- Already set by boardVehicle()

    -- Calculate velocity and update direction
    if movement_input then
        vx = move_x * ride_speed
        vy = move_y * ride_speed

        -- Update direction based on movement
        local abs_x = math.abs(move_x)
        local abs_y = math.abs(move_y)
        if abs_x > abs_y then
            player.direction = move_x > 0 and "right" or "left"
        else
            player.direction = move_y > 0 and "down" or "up"
        end
    end

    -- Get ride effect from vehicle config
    local vehicle = player.boarded_vehicle
    local ride_effect = vehicle and vehicle.ride_effect or "animated"

    -- Select animation: ride_move when moving, ride_idle when stopped
    local anim_type = movement_input and "ride_move_" or "ride_idle_"
    local anim_key = anim_type .. player.direction

    if player.animations[anim_key] then
        player.anim = player.animations[anim_key]

        -- Apply ride effect
        if ride_effect == "vibration" then
            -- Vibration: don't update animation (fixed frame), always vibrate (engine)
            -- Higher RPM when moving = higher frequency vibration
            local intensity = vehicle.vibration_intensity or 1
            local speed = movement_input
                and (vehicle.vibration_speed_move or 120)
                or (vehicle.vibration_speed_idle or 60)
            local offset = math.sin(love.timer.getTime() * speed) * intensity
            player.ride_vibration_offset = offset
            vehicle.vibration_offset = offset  -- Apply to vehicle too
        else
            -- Animated: update animation frames normally
            player.anim:update(dt)
            player.ride_vibration_offset = 0
            if vehicle then vehicle.vibration_offset = 0 end
        end
    else
        -- Fallback to idle if ride animation not defined
        player.anim = player.animations["idle_" .. player.direction]
        player.ride_vibration_offset = 0
    end

    player.state = "riding"
    return vx, vy, movement_input
end

-- Process movement input and update animation
local function handleMovementInput(player, dt)
    local vx, vy = 0, 0
    local is_moving = false
    local movement_input = false

    -- Check for movement input (keyboard or gamepad)
    -- is_walk_input: true if CTRL held (keyboard) or stick magnitude < 0.5 (gamepad)
    local move_x, move_y, is_walk_input = input:getMovement()

    -- Handle riding state separately (static pose)
    if player.is_boarded then
        return handleRidingState(player, dt, move_x, move_y)
    end

    -- In platformer mode, ignore vertical input (W/S keys used for jump/crouch)
    if player.game_mode == "platformer" then
        move_y = 0
    end

    movement_input = (math.abs(move_x) > 0.01 or math.abs(move_y) > 0.01)

    if player.state ~= "attacking" and not player.parry_active and not player.dodge_active and not debug:IsHandMarkingActive() then
        local move_direction = nil

        -- Determine move type: walk if map forces it, CTRL held, or partial stick
        -- default_move is "walk" for indoor maps (move_mode="walk")
        local use_walk = (player.default_move == "walk") or is_walk_input
        local move_type = use_walk and "walk" or "run"

        -- Game mode specific movement
        if player.game_mode == "platformer" then
            -- Platformer mode: horizontal movement only, jump handled separately
            if movement_input then
                -- Only left/right direction
                if math.abs(move_x) > 0.01 then
                    move_direction = move_x > 0 and "right" or "left"
                end

                local is_backpedaling = isBackpedaling(player, move_direction)

                -- Use walk_speed if walking, backpedaling, or walk_speed is defined
                local current_speed = player.speed
                if (use_walk or is_backpedaling) and player.walk_speed then
                    current_speed = player.walk_speed
                end
                vx = move_x * current_speed
                vy = 0 -- Gravity handles vertical movement
                is_moving = math.abs(move_x) > 0.01

                -- Store input direction for jump
                player.last_input_x = move_x
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
                -- Determine direction from movement vector first
                local abs_x = math.abs(move_x)
                local abs_y = math.abs(move_y)

                if abs_x > abs_y then
                    move_direction = move_x > 0 and "right" or "left"
                else
                    move_direction = move_y > 0 and "down" or "up"
                end

                local is_backpedaling = isBackpedaling(player, move_direction)

                -- Use walk_speed if walking, backpedaling, or walk_speed is defined
                local current_speed = player.speed
                if (use_walk or is_backpedaling) and player.walk_speed then
                    current_speed = player.walk_speed
                end
                vx = move_x * current_speed
                vy = move_y * current_speed
                is_moving = true
            end
        end

        if not player.weapon_drawn and move_direction then
            player.direction = move_direction
            updateFacingAngleFromDirection(player)
        end

        if is_moving then
            local is_backpedaling = isBackpedaling(player, move_direction)

            -- Force walk animation when backpedaling
            local final_move_type = is_backpedaling and "walk" or move_type

            local is_jumping = isJumping(player)

            -- Check for jump animation (moving jump)
            local anim_key
            if is_jumping then
                -- Moving jump: jump_move → jump → walk fallback
                anim_key = "jump_move_" .. player.direction
                if not player.animations[anim_key] then
                    anim_key = "jump_" .. player.direction
                end
                if not player.animations[anim_key] then
                    anim_key = "walk_" .. player.direction
                end
            else
                -- Use walk animation if walk mode, run animation if run mode
                -- Fallback to walk if run animation doesn't exist
                anim_key = final_move_type .. "_" .. player.direction
                if not player.animations[anim_key] then
                    -- Fallback to walk animation if run doesn't exist
                    anim_key = "walk_" .. player.direction
                end
            end
            player.anim = player.animations[anim_key]
            player.anim:update(dt)
            player.state = final_move_type == "run" and "running" or "walking"
        else
            local is_jumping = isJumping(player)

            -- Check for jump animation (standing jump)
            local anim_key
            if is_jumping then
                -- Standing jump: jump → idle fallback
                anim_key = "jump_" .. player.direction
                if not player.animations[anim_key] then
                    anim_key = "idle_" .. player.direction
                end
            else
                anim_key = "idle_" .. player.direction
            end
            player.anim = player.animations[anim_key]
            player.anim:update(dt)
            if player.state ~= "attacking" and not player.parry_active then
                player.state = "idle"
            end
        end
    end

    return vx, vy, movement_input
end

-- Get combo animation suffix
local function getComboAnimSuffix(player)
    if player.combo_count <= 1 then
        return ""
    end
    local combo_config = player.config and player.config.combo
    if combo_config and combo_config.attacks and combo_config.attacks[player.combo_count] then
        return combo_config.attacks[player.combo_count].anim_suffix or ""
    end
    return "_" .. player.combo_count
end

-- Handle special states (dodge, attack, parry, debug)
local function handleSpecialStates(player, dt, movement_input)
    local vx, vy = 0, 0

    if player.dodge_active then
        vx = player.dodge_direction_x * player.dodge_speed
        vy = player.dodge_direction_y * player.dodge_speed
        local move_type = player.default_move or "walk"
        player.anim = player.animations[move_type .. "_" .. player.direction]
        player.anim:update(dt * 2)
    elseif player.state == "attacking" then
        -- Get combo animation suffix (e.g., "", "_2", "_3")
        local suffix = getComboAnimSuffix(player)
        local anim_key = "attack" .. suffix .. "_" .. player.direction

        -- Fall back to base attack animation if combo animation doesn't exist
        if not player.animations[anim_key] then
            anim_key = "attack_" .. player.direction
        end

        player.anim = player.animations[anim_key]
        if not debug:IsHandMarkingActive() then
            player.anim:update(dt)
        end
    elseif player.parry_active then
        player.anim = player.animations["idle_" .. player.direction]
        player.anim:update(dt)
    elseif debug:IsHandMarkingActive() then
        local current_anim_name
        if movement_input then
            local move_type = player.default_move or "walk"
            player.state = move_type == "run" and "running" or "walking"
            current_anim_name = move_type .. "_" .. player.direction
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

-- Update weapon position and animation
local function handleWeaponUpdate(player, dt, current_frame_index)
    if player.weapon then
        local weapon_x, weapon_y = getWeaponPosition(player)

        player.weapon:update(dt, weapon_x, weapon_y, player.facing_angle,
            player.direction, player.current_anim_name, current_frame_index, debug:IsHandMarkingActive())
    end
end

-- Helper: create animation from config frame definition
local function createAnimation(grid, frame_def, duration)
    if type(frame_def[1]) == "table" then
        -- Multiple ranges: {{"5-8", 4}, {"1-2", 5}}
        local args = {}
        for _, range in ipairs(frame_def) do
            table.insert(args, range[1])
            table.insert(args, range[2])
        end
        return anim8.newAnimation(grid(unpack(args)), duration)
    else
        -- Single range: {"1-4", 3}
        return anim8.newAnimation(grid(frame_def[1], frame_def[2]), duration)
    end
end

-- Default animation frames (fallback)
local DEFAULT_FRAMES = {
    walk_up    = {"1-4", 4},
    walk_down  = {"1-4", 3},
    walk_left  = {{"5-8", 4}, {"1-2", 5}},
    walk_right = {"3-8", 5},

    idle_up    = {"5-8", 1},
    idle_down  = {"1-4", 1},
    idle_left  = {"1-4", 2},
    idle_right = {"5-8", 2},

    attack_down  = {"1-4", 11},
    attack_up    = {"5-8", 11},
    attack_left  = {"1-4", 12},
    attack_right = {"5-8", 12},
}

-- Default animation durations
local DEFAULT_DURATIONS = {
    walk = 0.1,
    run = 0.08,
    idle = 0.15,
    attack = 0.08,
    jump = 0.15,
    jump_move = 0.12,
}

-- Default move type
local DEFAULT_MOVE = "walk"

function animation.initialize(player, sprite_sheet, sprite_width, sprite_height)
    player.spriteSheet = love.graphics.newImage(sprite_sheet)
    player.grid = anim8.newGrid(sprite_width, sprite_height, player.spriteSheet:getWidth(), player.spriteSheet:getHeight())

    -- Use config if available, otherwise use defaults
    local anim_config = player.config and player.config.animations
    local frames = anim_config and anim_config.frames or DEFAULT_FRAMES
    local durations = anim_config and anim_config.durations or DEFAULT_DURATIONS

    -- Determine default move type (walk or run)
    player.default_move = anim_config and anim_config.default_move or DEFAULT_MOVE

    player.animations = {}

    -- Walk animations
    if frames.walk_up then
        player.animations.walk_up = createAnimation(player.grid, frames.walk_up, durations.walk)
        player.animations.walk_down = createAnimation(player.grid, frames.walk_down, durations.walk)
        player.animations.walk_left = createAnimation(player.grid, frames.walk_left, durations.walk)
        player.animations.walk_right = createAnimation(player.grid, frames.walk_right, durations.walk)
    end

    -- Run animations (optional)
    if frames.run_up then
        player.animations.run_up = createAnimation(player.grid, frames.run_up, durations.run)
        player.animations.run_down = createAnimation(player.grid, frames.run_down, durations.run)
        player.animations.run_left = createAnimation(player.grid, frames.run_left, durations.run)
        player.animations.run_right = createAnimation(player.grid, frames.run_right, durations.run)
    end

    -- Idle animations
    player.animations.idle_up = createAnimation(player.grid, frames.idle_up, durations.idle)
    player.animations.idle_down = createAnimation(player.grid, frames.idle_down, durations.idle)
    player.animations.idle_left = createAnimation(player.grid, frames.idle_left, durations.idle)
    player.animations.idle_right = createAnimation(player.grid, frames.idle_right, durations.idle)

    -- Attack animations
    player.animations.attack_down = createAnimation(player.grid, frames.attack_down, durations.attack)
    player.animations.attack_up = createAnimation(player.grid, frames.attack_up, durations.attack)
    player.animations.attack_left = createAnimation(player.grid, frames.attack_left, durations.attack)
    player.animations.attack_right = createAnimation(player.grid, frames.attack_right, durations.attack)

    -- Combo attack 2 animations (optional)
    if frames.attack_2_down then
        player.animations.attack_2_down = createAnimation(player.grid, frames.attack_2_down, durations.attack_2 or durations.attack)
        player.animations.attack_2_up = createAnimation(player.grid, frames.attack_2_up, durations.attack_2 or durations.attack)
        player.animations.attack_2_left = createAnimation(player.grid, frames.attack_2_left, durations.attack_2 or durations.attack)
        player.animations.attack_2_right = createAnimation(player.grid, frames.attack_2_right, durations.attack_2 or durations.attack)
    end

    -- Combo attack 3 animations (optional)
    if frames.attack_3_down then
        player.animations.attack_3_down = createAnimation(player.grid, frames.attack_3_down, durations.attack_3 or durations.attack)
        player.animations.attack_3_up = createAnimation(player.grid, frames.attack_3_up, durations.attack_3 or durations.attack)
        player.animations.attack_3_left = createAnimation(player.grid, frames.attack_3_left, durations.attack_3 or durations.attack)
        player.animations.attack_3_right = createAnimation(player.grid, frames.attack_3_right, durations.attack_3 or durations.attack)
    end

    -- Jump animations (optional - standing jump)
    if frames.jump_up then
        player.animations.jump_up = createAnimation(player.grid, frames.jump_up, durations.jump or 0.15)
        player.animations.jump_down = createAnimation(player.grid, frames.jump_down, durations.jump or 0.15)
        player.animations.jump_left = createAnimation(player.grid, frames.jump_left, durations.jump or 0.15)
        player.animations.jump_right = createAnimation(player.grid, frames.jump_right, durations.jump or 0.15)
    end

    -- Jump move animations (optional - moving jump)
    if frames.jump_move_up then
        player.animations.jump_move_up = createAnimation(player.grid, frames.jump_move_up, durations.jump_move or 0.12)
        player.animations.jump_move_down = createAnimation(player.grid, frames.jump_move_down, durations.jump_move or 0.12)
        player.animations.jump_move_left = createAnimation(player.grid, frames.jump_move_left, durations.jump_move or 0.12)
        player.animations.jump_move_right = createAnimation(player.grid, frames.jump_move_right, durations.jump_move or 0.12)
    end

    -- Ride idle animations (optional - static pose when stopped on vehicle)
    if frames.ride_idle_up then
        player.animations.ride_idle_up = createAnimation(player.grid, frames.ride_idle_up, durations.ride_idle or 0.15)
        player.animations.ride_idle_down = createAnimation(player.grid, frames.ride_idle_down, durations.ride_idle or 0.15)
        player.animations.ride_idle_left = createAnimation(player.grid, frames.ride_idle_left, durations.ride_idle or 0.15)
        player.animations.ride_idle_right = createAnimation(player.grid, frames.ride_idle_right, durations.ride_idle or 0.15)
    end

    -- Ride move animations (optional - moving on vehicle)
    if frames.ride_move_up then
        player.animations.ride_move_up = createAnimation(player.grid, frames.ride_move_up, durations.ride_move or 0.1)
        player.animations.ride_move_down = createAnimation(player.grid, frames.ride_move_down, durations.ride_move or 0.1)
        player.animations.ride_move_left = createAnimation(player.grid, frames.ride_move_left, durations.ride_move or 0.1)
        player.animations.ride_move_right = createAnimation(player.grid, frames.ride_move_right, durations.ride_move or 0.1)
    end

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

    -- NOTE: Attack end and recovery state handled by combat.updateTimers()

    -- Handle recovery state (no movement allowed)
    if player.state == "recovering" then
        player.anim = player.animations["idle_" .. player.direction]
        player.anim:update(dt)
        return 0, 0  -- No movement during recovery
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

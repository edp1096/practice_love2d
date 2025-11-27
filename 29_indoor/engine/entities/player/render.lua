-- entities/player/render.lua
-- Rendering: draw player sprite, weapon, effects

local debug = require "engine.core.debug"

local render = {}

function render.draw(player)
    local draw_x = player.x + player.hit_shake_x
    local draw_y = player.y + player.hit_shake_y

    -- Apply topdown jump offset (visual only, moves sprite up)
    -- topdown_jump_height is negative when jumping (starts at 0, goes to -50, back to 0)
    if player.game_mode == "topdown" and player.topdown_is_jumping then
        draw_y = draw_y + player.topdown_jump_height
    end

    -- NOTE: Stair movement is now handled by adjusting velocity in moveEntity()
    -- No visual offset needed - the collider actually moves diagonally on stairs

    -- Shadow (stays on ground in platformer mode with dynamic scaling)
    -- Shadow at character feet (center + half collider height)
    local shadow_y = player.y + (player.collider_height / 2)
    local shadow_scale = 1.0
    local shadow_alpha = 0.4

    -- Handle topdown jump shadow scaling
    if player.game_mode == "topdown" and player.topdown_is_jumping then
        -- Scale shadow based on jump height (gets smaller when higher)
        -- topdown_jump_height is negative, so use abs() for scaling
        local height = math.abs(player.topdown_jump_height)
        shadow_scale = math.max(0.3, 1.0 - (height / 100))
        shadow_alpha = math.max(0.1, 0.4 - (height / 125))
    elseif player.game_mode == "platformer" and player.ground_y then
        -- In platformer mode, shadow stays at ground level
        -- ground_y is the Y coordinate of the ground surface from raycast
        -- We want shadow ON the ground, not below it
        shadow_y = player.ground_y

        -- Calculate height difference (distance from player's feet to ground)
        -- Player's feet are at: center + half collider height
        local player_feet_y = player.y + (player.collider_height / 2)
        local height_diff = player.ground_y - player_feet_y

        -- Scale shadow based on height (gets smaller when higher)
        -- At height 0: scale = 1.0, at height 200: scale = 0.3
        shadow_scale = math.max(0.3, 1.0 - (height_diff / 300))

        -- Fade shadow based on height (gets more transparent when higher)
        shadow_alpha = math.max(0.1, 0.4 - (height_diff / 500))
    end

    love.graphics.setColor(0, 0, 0, shadow_alpha)
    local shadow_width = player.collider_width * 0.625 * shadow_scale
    local shadow_height = player.collider_width * 0.175 * shadow_scale
    love.graphics.ellipse("fill", draw_x, shadow_y, shadow_width, shadow_height)
    love.graphics.setColor(1, 1, 1, 1)

    -- Parry shield
    if player.parry_active then
        local shield_alpha = 0.3 + 0.2 * math.sin(love.timer.getTime() * 10)
        love.graphics.setColor(0.3, 0.6, 1, shield_alpha)
        local shield_radius = player.collider_width * 0.8
        love.graphics.circle("fill", draw_x, draw_y, shield_radius)
        love.graphics.setColor(0.5, 0.8, 1, 0.6)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", draw_x, draw_y, shield_radius)
        love.graphics.setLineWidth(1)
    end

    -- Blink during invincibility
    local should_draw = true
    if player.invincible_timer > 0 or player.dodge_invincible_timer > 0 then
        local blink_cycle = math.floor(love.timer.getTime() / 0.1)
        should_draw = (blink_cycle % 2 == 0)
    end

    -- Evade effect: semi-transparent glow (no blinking, no afterimages)
    local evade_alpha = nil
    if player.evade_active then
        -- Pulsing transparency effect (0.1 ~ 0.5 range for strong transparency)
        local pulse = 0.3 + 0.2 * math.sin(love.timer.getTime() * 12)
        evade_alpha = pulse
    end

    -- Dodge afterimages
    if player.dodge_active then
        local progress = 1 - (player.dodge_timer / player.dodge_duration)
        for i = 1, 3 do
            local offset = i * 0.05
            if progress > offset then
                local alpha = 0.3 - (i * 0.1)
                love.graphics.setColor(1, 1, 1, alpha)
                local afterimage_x = draw_x - (player.dodge_direction_x * i * 15)
                local afterimage_y = draw_y - (player.dodge_direction_y * i * 15)
                player.anim:draw(player.spriteSheet, afterimage_x, afterimage_y, nil, player.sprite_scale, player.sprite_scale, player.sprite_origin_x, player.sprite_origin_y)
            end
        end
        -- Reset color after afterimages
        love.graphics.setColor(1, 1, 1, 1)
    end

    if should_draw then
        -- Evade glow (different from parry - greenish tint)
        if evade_alpha then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(0.3, 1, 0.6, 0.3)
            player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, player.sprite_scale, player.sprite_scale, player.sprite_origin_x, player.sprite_origin_y)
            love.graphics.setBlendMode("alpha")
        end

        -- Parry glow
        if player.parry_active then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(0.3, 0.6, 1, 0.4)
            player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, player.sprite_scale, player.sprite_scale, player.sprite_origin_x, player.sprite_origin_y)
            love.graphics.setBlendMode("alpha")
        end

        -- Normal sprite (with evade transparency if active)
        if evade_alpha then
            love.graphics.setColor(1, 1, 1, evade_alpha)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, player.sprite_scale, player.sprite_scale, player.sprite_origin_x, player.sprite_origin_y)

        -- Hit flash
        if player.hit_flash_timer > 0 then
            local flash_intensity = player.hit_flash_timer / 0.2
            love.graphics.setBlendMode("add")
            love.graphics.setColor(1, 1, 1, flash_intensity * 0.7)
            player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, player.sprite_scale, player.sprite_scale, player.sprite_origin_x, player.sprite_origin_y)
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
        end

        -- Parry success flash
        if player.parry_success_timer > 0 then
            local flash_intensity = player.parry_success_timer / 0.5
            love.graphics.setBlendMode("add")
            if player.parry_perfect then
                love.graphics.setColor(1, 1, 0, flash_intensity * 0.9)
            else
                love.graphics.setColor(0.5, 0.8, 1, flash_intensity * 0.7)
            end
            player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, player.sprite_scale, player.sprite_scale, player.sprite_origin_x, player.sprite_origin_y)
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- Debug colliders (moved to debug/render.lua)
    debug:drawPlayerColliders(player)
end

function render.drawWeapon(player)
    if not player.weapon then
        return
    end
    player.weapon:draw(debug.enabled)
end

function render.drawAll(player)
    -- No weapon equipped
    if not player.weapon then
        render.draw(player)
        return
    end

    -- Weapon sheathed
    if not player.weapon_drawn then
        render.draw(player)
        player.weapon:drawSheathParticles()
        return
    end

    -- Weapon drawn
    if player.direction == "left" or player.direction == "up" then
        render.drawWeapon(player)
        render.draw(player)
        player.weapon:drawSheathParticles()
    else
        render.draw(player)
        render.drawWeapon(player)
        player.weapon:drawSheathParticles()
    end
end

function render.drawDebug(player)
    if not debug.enabled then return end
    debug:DrawHandMarkers(player)
end

return render

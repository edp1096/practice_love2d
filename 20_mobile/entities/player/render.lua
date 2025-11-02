-- entities/player/render.lua
-- Rendering: draw player sprite, weapon, effects

local debug = require "systems.debug"

local render = {}

function render.draw(player)
    local draw_x = player.x + player.hit_shake_x
    local draw_y = player.y + player.hit_shake_y

    -- Shadow (stays on ground in platformer mode with dynamic scaling)
    local shadow_y = draw_y + 50  -- Topdown: shadow below player
    local shadow_scale = 1.0
    local shadow_alpha = 0.4

    if player.game_mode == "platformer" and player.ground_y then
        -- In platformer mode, shadow stays at ground level
        -- ground_y is the Y coordinate of the ground surface from raycast
        -- We want shadow ON the ground, not below it
        shadow_y = player.ground_y

        -- Calculate height difference (distance from player's feet to ground)
        -- Player's feet are at: player.y + (player.height / 2)
        local player_feet_y = player.y + (player.height / 2)
        local height_diff = player.ground_y - player_feet_y

        -- Scale shadow based on height (gets smaller when higher)
        -- At height 0: scale = 1.0, at height 200: scale = 0.3
        shadow_scale = math.max(0.3, 1.0 - (height_diff / 300))

        -- Fade shadow based on height (gets more transparent when higher)
        shadow_alpha = math.max(0.1, 0.4 - (height_diff / 500))
    end

    love.graphics.setColor(0, 0, 0, shadow_alpha)
    love.graphics.ellipse("fill", draw_x, shadow_y, 28 * shadow_scale, 8 * shadow_scale)
    love.graphics.setColor(1, 1, 1, 1)

    -- Parry shield
    if player.parry_active then
        local shield_alpha = 0.3 + 0.2 * math.sin(love.timer.getTime() * 10)
        love.graphics.setColor(0.3, 0.6, 1, shield_alpha)
        love.graphics.circle("fill", draw_x, draw_y, 40)
        love.graphics.setColor(0.5, 0.8, 1, 0.6)
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", draw_x, draw_y, 40)
        love.graphics.setLineWidth(1)
    end

    -- Blink during invincibility
    local should_draw = true
    if player.invincible_timer > 0 or player.dodge_invincible_timer > 0 then
        local blink_cycle = math.floor(love.timer.getTime() / 0.1)
        should_draw = (blink_cycle % 2 == 0)
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
                player.anim:draw(player.spriteSheet, afterimage_x, afterimage_y, nil, 3, nil, 24, 24)
            end
        end
    end

    if should_draw then
        -- Parry glow
        if player.parry_active then
            love.graphics.setBlendMode("add")
            love.graphics.setColor(0.3, 0.6, 1, 0.4)
            player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)
            love.graphics.setBlendMode("alpha")
        end

        -- Normal sprite
        love.graphics.setColor(1, 1, 1, 1)
        player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)

        -- Hit flash
        if player.hit_flash_timer > 0 then
            local flash_intensity = player.hit_flash_timer / 0.2
            love.graphics.setBlendMode("add")
            love.graphics.setColor(1, 1, 1, flash_intensity * 0.7)
            player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)
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
            player.anim:draw(player.spriteSheet, draw_x, draw_y, nil, 3, nil, 24, 24)
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- Debug hitbox
    if debug.show_colliders and player.collider then
        love.graphics.setColor(0, 1, 0, 0.3)
        love.graphics.rectangle("fill", player.x - player.width / 2, player.y - player.height / 2, player.width, player.height)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function render.drawWeapon(player)
    player.weapon:draw(debug.enabled)
end

function render.drawAll(player)
    if not player.weapon_drawn then
        render.draw(player)
        player.weapon:drawSheathParticles()
        return
    end

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

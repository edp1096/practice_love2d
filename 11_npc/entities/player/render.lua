-- entities/player/render.lua
-- Rendering: draw player sprite, weapon, effects

local debug = require "systems.debug"

local render = {}

function render.draw(player)
    local draw_x = player.x + player.hit_shake_x
    local draw_y = player.y + player.hit_shake_y

    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", draw_x, draw_y + 50, 28, 8)
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
    player.weapon:draw(debug.debug_mode)
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
    if not debug.debug_mode then return end
    debug:DrawHandMarkers(player)
end

return render

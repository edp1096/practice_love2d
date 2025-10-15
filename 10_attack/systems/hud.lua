-- systems/hud.lua
-- HUD and UI elements

local hud = {}

function hud:draw_health_bar(x, y, w, h, hp, max_hp)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 14)

    love.graphics.setColor(0.3, 0, 0, 1)
    love.graphics.rectangle("fill", x, y, w, h)

    local health_ratio = hp / max_hp
    if health_ratio < 0.3 then
        love.graphics.setColor(1, 0, 0, 1)
    elseif health_ratio < 0.6 then
        love.graphics.setColor(1, 1, 0, 1)
    else
        love.graphics.setColor(0, 1, 0, 1)
    end
    love.graphics.rectangle("fill", x, y, w * health_ratio, h)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("HP: %d / %d", hp, max_hp), x + 5, y + 3)
end

function hud:draw_cooldown(x, y, size, cd, max_cd, label, key_hint)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 2, y - 2, size + 4, 44)

    love.graphics.setColor(0.2, 0.2, 0.3, 1)
    love.graphics.rectangle("fill", x, y, size, 20)

    if cd > 0 then
        local cd_ratio = 1 - (cd / max_cd)
        love.graphics.setColor(0.3, 0.5, 1, 1)
        love.graphics.rectangle("fill", x, y, size * cd_ratio, 20)

        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(string.format("%s CD: %.1f", label, cd), x + 5, y + 3)
    else
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(0.3, 1, 0.3, pulse)
        love.graphics.rectangle("fill", x, y, size, 20)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(string.format("%s READY! (%s)", label, key_hint), x + 5, y + 3)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function hud:draw_parry_success(player, screen_w, screen_h)
    if player.parry_success_timer <= 0 then return end

    local text = player.parry_perfect and "PERFECT PARRY!" or "PARRY!"
    local font_size = player.parry_perfect and 48 or 36
    local font = love.graphics.newFont(font_size)
    love.graphics.setFont(font)

    local alpha = player.parry_success_timer / 0.5
    if player.parry_perfect then
        love.graphics.setColor(1, 1, 0, alpha)
    else
        love.graphics.setColor(0.5, 0.8, 1, alpha)
    end

    local text_width = font:getWidth(text)
    love.graphics.print(text, screen_w / 2 - text_width / 2, 150)

    love.graphics.setColor(1, 1, 1, 1)
end

function hud:draw_slow_motion_vignette(time_scale, screen_w, screen_h)
    if time_scale >= 0.9 then return end

    local vignette_alpha = (1.0 - time_scale) * 0.3
    love.graphics.setColor(0.2, 0.4, 0.6, vignette_alpha)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    love.graphics.setColor(1, 1, 1, 1)
end

function hud:draw_debug_panel(player, debug_mode)
    if not debug_mode then return end

    local marking_info = player.current_anim_name and {
        animation = player.current_anim_name,
        frame = 1,
        frame_count = 4
    } or nil

    local panel_height = marking_info and 280 or 230

    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, 280, panel_height)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
    love.graphics.print(string.format("Player: %.1f, %.1f", player.x, player.y), 10, 30)
    love.graphics.print("Press ESC to pause", 10, 50)
    love.graphics.print("Left Click to Attack", 10, 70)
    love.graphics.print("Right Click to Parry", 10, 90)
    love.graphics.print("Space to Dodge/Roll", 10, 110)
    love.graphics.print("H = Hand Marking Mode", 10, 130)
    love.graphics.print("P = Mark Position", 10, 150)

    local state_text = "State: " .. player.state
    if player.attack_cooldown > 0 then
        state_text = state_text .. string.format(" (CD: %.1f)", player.attack_cooldown)
    end
    if player.dodge_active then
        state_text = state_text .. " [DODGING]"
    end
    love.graphics.print(state_text, 10, 170)
end

return hud

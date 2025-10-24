-- systems/hud.lua
-- HUD and UI elements with unified debug system

local hud = {}

hud.small_font = love.graphics.newFont(11)
hud.tiny_font = love.graphics.newFont(10)

function hud:draw_health_bar(x, y, w, h, hp, max_hp)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 22)

    love.graphics.setColor(0.3, 0, 0, 1)
    love.graphics.rectangle("fill", x, y, w, h)

    local health_ratio = hp / max_hp
    if health_ratio < 0.3 then
        love.graphics.setColor(0.6, 0.2, 0.2, 1)
    elseif health_ratio < 0.6 then
        love.graphics.setColor(0.7, 0.2, 0.2, 1)
    else
        love.graphics.setColor(0.8, 0.2, 0.2, 1)
    end
    love.graphics.rectangle("fill", x, y, w * health_ratio, h)

    love.graphics.setFont(self.small_font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(string.format("HP: %d / %d", hp, max_hp), x + 5, y + 3)
end

function hud:draw_cooldown(x, y, size, cd, max_cd, label, key_hint)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 2, y - 2, size + 4, 44)

    love.graphics.setColor(0.2, 0.2, 0.3, 1)
    love.graphics.rectangle("fill", x, y, size, 20)

    love.graphics.setFont(self.small_font)

    if cd > 0 then
        local cd_ratio = 1 - (cd / max_cd)
        love.graphics.setColor(0.3, 0.5, 1, 1)
        love.graphics.rectangle("fill", x, y, size * cd_ratio, 20)

        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(string.format("%s CD: %.1f", label, cd), x + 5, y + 3)
    else
        local pulse = 0.7 + 0.3 * math.sin(love.timer.getTime() * 3)
        love.graphics.setColor(0.2, 0.7, 0.2, pulse)
        love.graphics.rectangle("fill", x, y, size, 20)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(string.format("%s READY! (%s)", label, key_hint), x + 5, y + 3)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function hud:draw_parry_success(player, screen_w, screen_h)
    if player.parry_success_timer <= 0 then return end

    local text = player.parry_perfect and "PERFECT PARRY!" or "PARRY!"
    local font_size = player.parry_perfect and 32 or 24
    local font = love.graphics.newFont(font_size)
    love.graphics.setFont(font)

    local alpha = player.parry_success_timer / 0.5
    if player.parry_perfect then
        love.graphics.setColor(1, 1, 0, alpha)
    else
        love.graphics.setColor(0.5, 0.8, 1, alpha)
    end

    local text_width = font:getWidth(text)
    love.graphics.print(text, screen_w / 2 - text_width / 2, 100)

    love.graphics.setColor(1, 1, 1, 1)
end

function hud:draw_slow_motion_vignette(time_scale, screen_w, screen_h)
    if time_scale >= 0.9 then return end

    local vignette_alpha = (1.0 - time_scale) * 0.3
    love.graphics.setColor(0.2, 0.4, 0.6, vignette_alpha)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    love.graphics.setColor(1, 1, 1, 1)
end

function hud:draw_debug_panel(player, current_save_slot)
    -- Use unified debug system
    local debug = require "systems.debug"
    if not debug.enabled then return end

    local marking_info = player.current_anim_name and {
        animation = player.current_anim_name,
        frame = 1,
        frame_count = 4
    } or nil

    local panel_height = marking_info and 200 or 170

    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, 220, panel_height)

    love.graphics.setFont(self.tiny_font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 8, 8)
    love.graphics.print(string.format("Player: %.1f, %.1f", player.x, player.y), 8, 22)

    if current_save_slot then
        love.graphics.print("Current Slot: " .. current_save_slot, 8, 36)
        love.graphics.print("Press ESC to pause", 8, 50)
        love.graphics.print("Left Click to Attack", 8, 64)
        love.graphics.print("Right Click to Parry", 8, 78)
        love.graphics.print("Space to Dodge/Roll", 8, 92)
        love.graphics.print("H = Hand Marking Mode", 8, 106)
        love.graphics.print("P = Mark Anchor Position", 8, 120)
    else
        love.graphics.print("Press ESC to pause", 8, 36)
        love.graphics.print("Left Click to Attack", 8, 50)
        love.graphics.print("Right Click to Parry", 8, 64)
        love.graphics.print("Space to Dodge/Roll", 8, 78)
        love.graphics.print("H = Hand Marking Mode", 8, 92)
        love.graphics.print("P = Mark Anchor Position", 8, 106)
    end

    local state_text = "State: " .. player.state
    if player.attack_cooldown > 0 then
        state_text = state_text .. string.format(" (CD: %.1f)", player.attack_cooldown)
    end
    if player.dodge_active then
        state_text = state_text .. " [DODGING]"
    end
    local state_y = current_save_slot and 134 or 120
    love.graphics.print(state_text, 8, state_y)
end

function hud:draw_inventory(inventory, screen_w, screen_h)
    if not inventory or #inventory.items == 0 then
        return
    end

    local slot_size = 50
    local slot_spacing = 8
    local start_x = screen_w - (slot_size + slot_spacing) * math.min(#inventory.items, 5) - 20
    local start_y = screen_h - slot_size - 20

    love.graphics.setFont(self.small_font)

    for i, item in ipairs(inventory.items) do
        local x = start_x + (i - 1) * (slot_size + slot_spacing)
        local y = start_y

        -- Background
        if i == inventory.selected_slot then
            love.graphics.setColor(0.3, 0.5, 0.8, 0.9)
        else
            love.graphics.setColor(0.2, 0.2, 0.3, 0.8)
        end
        love.graphics.rectangle("fill", x, y, slot_size, slot_size)

        -- Border
        if i == inventory.selected_slot then
            love.graphics.setColor(0.5, 0.8, 1, 1)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.4, 0.4, 0.5, 1)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", x, y, slot_size, slot_size)

        -- Item icon (text representation for now)
        love.graphics.setColor(1, 1, 1, 1)
        local icon_text = "HP"
        if item.type == "small_potion" then
            love.graphics.setColor(0.5, 1, 0.5, 1)
        elseif item.type == "large_potion" then
            love.graphics.setColor(0.3, 1, 0.8, 1)
        end
        love.graphics.print(icon_text, x + 10, y + 8)

        -- Quantity
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("x" .. item.quantity, x + 5, y + 30)

        -- Slot number
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(tostring(i), x + 5, y + 3)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

return hud

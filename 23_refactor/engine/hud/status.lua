-- systems/hud.lua
-- HUD and UI elements with unified debug system

local fonts = require "engine.utils.fonts"
local text_ui = require "engine.ui.text"
local shapes = require "engine.ui.shapes"

local hud = {}

hud.small_font = love.graphics.newFont(11)
hud.tiny_font = love.graphics.newFont(10)
hud.parry_font = love.graphics.newFont(24)
hud.perfect_parry_font = love.graphics.newFont(32)

function hud:draw_health_bar(x, y, w, h, hp, max_hp)
    shapes:drawHealthBar(x, y, w, h, hp, max_hp, true, self.small_font)
end

function hud:draw_cooldown(x, y, size, cd, max_cd, label, key_hint)
    -- Background panel
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 2, y - 2, size + 4, 44)

    -- Cooldown bar
    shapes:drawCooldown(x, y, size, 20, cd, max_cd)

    -- Label
    if cd > 0 then
        text_ui:draw(string.format("%s CD: %.1f", label, cd), x + 5, y + 3, {0.7, 0.7, 0.7, 1}, self.small_font)
    else
        text_ui:draw(string.format("%s READY! (%s)", label, key_hint), x + 5, y + 3, {1, 1, 1, 1}, self.small_font)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function hud:draw_parry_success(player, screen_w, screen_h)
    if player.parry_success_timer <= 0 then return end

    local text = player.parry_perfect and "PERFECT PARRY!" or "PARRY!"
    local font = player.parry_perfect and hud.perfect_parry_font or hud.parry_font

    local alpha = player.parry_success_timer / 0.5
    local color = player.parry_perfect and {1, 1, 0, alpha} or {0.5, 0.8, 1, alpha}

    local text_width = font:getWidth(text)
    text_ui:draw(text, screen_w / 2 - text_width / 2, 100, color, font)

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
    local debug = require "engine.debug"
    if not debug.enabled then return end

    local marking_info = player.current_anim_name and {
        animation = player.current_anim_name,
        frame = 1,
        frame_count = 4
    } or nil

    local panel_height = marking_info and 200 or 170

    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, 220, panel_height)

    local white = {1, 1, 1, 1}
    text_ui:draw("FPS: " .. love.timer.getFPS(), 8, 8, white, self.tiny_font)
    text_ui:draw(string.format("Player: %.1f, %.1f", player.x, player.y), 8, 22, white, self.tiny_font)

    if current_save_slot then
        text_ui:draw("Current Slot: " .. current_save_slot, 8, 36, white, self.tiny_font)
        text_ui:draw("Press ESC to pause", 8, 50, white, self.tiny_font)
        text_ui:draw("Left Click to Attack", 8, 64, white, self.tiny_font)
        text_ui:draw("Right Click to Parry", 8, 78, white, self.tiny_font)
        text_ui:draw("Space to Dodge/Roll", 8, 92, white, self.tiny_font)
        text_ui:draw("H = Hand Marking Mode", 8, 106, white, self.tiny_font)
        text_ui:draw("P = Mark Anchor Position", 8, 120, white, self.tiny_font)
    else
        text_ui:draw("Press ESC to pause", 8, 36, white, self.tiny_font)
        text_ui:draw("Left Click to Attack", 8, 50, white, self.tiny_font)
        text_ui:draw("Right Click to Parry", 8, 64, white, self.tiny_font)
        text_ui:draw("Space to Dodge/Roll", 8, 78, white, self.tiny_font)
        text_ui:draw("H = Hand Marking Mode", 8, 92, white, self.tiny_font)
        text_ui:draw("P = Mark Anchor Position", 8, 106, white, self.tiny_font)
    end

    local state_text = "State: " .. player.state
    if player.attack_cooldown > 0 then
        state_text = state_text .. string.format(" (CD: %.1f)", player.attack_cooldown)
    end
    if player.dodge_active then
        state_text = state_text .. " [DODGING]"
    end
    local state_y = current_save_slot and 134 or 120
    text_ui:draw(state_text, 8, state_y, white, self.tiny_font)
end

function hud:draw_inventory(inventory, screen_w, screen_h)
    if not inventory or #inventory.items == 0 then
        return
    end

    local slot_size = 50
    local slot_spacing = 8
    -- Position at top-left (11 o'clock), to the right of HP bar
    -- HP bar is at (pb.x + 12, pb.y + 12) with width 210 and background extends 2px
    local hp_bar_x = 12
    local hp_bar_y = 10  -- pb.y + 12 - 2 (background top)
    local hp_bar_width = 210
    local hp_bar_margin = 12

    local start_x = hp_bar_x + hp_bar_width + hp_bar_margin  -- Right of HP bar
    local start_y = hp_bar_y  -- Align top with HP bar background

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
        local icon_text = "HP"
        local icon_color = {1, 1, 1, 1}
        if item.type == "small_potion" then
            icon_color = {0.5, 1, 0.5, 1}
        elseif item.type == "large_potion" then
            icon_color = {0.3, 1, 0.8, 1}
        end
        text_ui:draw(icon_text, x + 10, y + 8, icon_color, self.small_font)

        -- Quantity
        text_ui:draw("x" .. item.quantity, x + 5, y + 30, {1, 1, 1, 1}, self.small_font)

        -- Slot number
        text_ui:draw(tostring(i), x + 5, y + 3, {0.7, 0.7, 0.7, 1}, self.small_font)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

return hud

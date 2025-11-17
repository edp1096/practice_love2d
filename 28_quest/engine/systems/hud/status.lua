-- systems/hud.lua
-- HUD and UI elements with unified debug system

local fonts = require "engine.utils.fonts"
local text_ui = require "engine.utils.text"
local shapes = require "engine.utils.shapes"
local colors = require "engine.ui.colors"

local hud = {}

hud.small_font = love.graphics.newFont(11)
hud.tiny_font = love.graphics.newFont(10)
hud.parry_font = love.graphics.newFont(24)
hud.perfect_parry_font = love.graphics.newFont(32)

function hud:draw_health_bar(x, y, w, h, hp, max_hp)
    shapes:drawHealthBar(x, y, w, h, hp, max_hp, true, self.small_font)
end

function hud:draw_exp_bar(x, y, w, h, current_exp, required_exp)
    -- Background
    colors:apply(colors.for_hud_exp_bg or {0.1, 0.1, 0.2}, 0.8)
    love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4)

    -- Border
    colors:apply(colors.for_hud_exp_border or {0.3, 0.3, 0.5})
    love.graphics.rectangle("line", x - 2, y - 2, w + 4, h + 4)

    -- Exp bar fill
    local progress = required_exp > 0 and (current_exp / required_exp) or 1.0
    local fill_width = math.floor(w * progress)

    if fill_width > 0 then
        colors:apply(colors.for_hud_exp_fill or {0.4, 0.6, 1.0})
        love.graphics.rectangle("fill", x, y, fill_width, h)
    end

    -- Text (exp / required)
    local text = string.format("%d / %d", current_exp, required_exp)
    local text_color = colors.WHITE or {1, 1, 1}
    text_ui:draw(text, x + w / 2 - self.small_font:getWidth(text) / 2, y + 3, text_color, self.small_font)

    colors:reset()
end

function hud:draw_level_info(x, y, level, gold)
    -- Level text
    local level_text = "Lv." .. level
    text_ui:draw(level_text, x, y, colors.for_hud_level or {1, 1, 0}, self.small_font)

    -- Gold text (right-aligned from x)
    local gold_text = "Gold: " .. gold
    local gold_x = x + 210 - self.small_font:getWidth(gold_text)
    text_ui:draw(gold_text, gold_x, y, colors.for_hud_gold or {1, 0.8, 0}, self.small_font)
end

function hud:draw_cooldown(x, y, size, cd, max_cd, label, key_hint)
    -- Background panel
    colors:apply(colors.for_hud_cooldown_bg)
    love.graphics.rectangle("fill", x - 2, y - 2, size + 4, 44)

    -- Cooldown bar
    shapes:drawCooldown(x, y, size, 20, cd, max_cd)

    -- Label
    if cd > 0 then
        text_ui:draw(string.format("%s CD: %.1f", label, cd), x + 5, y + 3, colors.for_hud_text_dim, self.small_font)
    else
        text_ui:draw(string.format("%s READY! (%s)", label, key_hint), x + 5, y + 3, colors.WHITE, self.small_font)
    end

    colors:reset()
end

function hud:draw_parry_success(player, screen_w, screen_h)
    if player.parry_success_timer <= 0 then return end

    local text = player.parry_perfect and "PERFECT PARRY!" or "PARRY!"
    local font = player.parry_perfect and hud.perfect_parry_font or hud.parry_font

    local alpha = player.parry_success_timer / 0.5
    local base_color = player.parry_perfect and colors.for_hud_parry_perfect or colors.for_hud_parry_normal
    local color = colors:withAlpha(base_color, alpha)

    local text_width = font:getWidth(text)
    text_ui:draw(text, screen_w / 2 - text_width / 2, 100, color, font)

    colors:reset()
end

function hud:draw_slow_motion_vignette(time_scale, screen_w, screen_h)
    if time_scale >= 0.9 then return end

    local vignette_alpha = (1.0 - time_scale) * 0.3
    colors:apply(colors.for_hud_slow_motion, vignette_alpha)
    love.graphics.rectangle("fill", 0, 0, screen_w, screen_h)
    colors:reset()
end

function hud:draw_debug_panel(player, current_save_slot)
    -- Use unified debug system
    local debug = require "engine.core.debug"
    if not debug.enabled then return end

    local marking_info = player.current_anim_name and {
        animation = player.current_anim_name,
        frame = 1,
        frame_count = 4
    } or nil

    local panel_height = marking_info and 200 or 170

    colors:apply(colors.for_debug_panel_bg)
    love.graphics.rectangle("fill", 0, 0, 220, panel_height)

    text_ui:draw("FPS: " .. love.timer.getFPS(), 8, 8, colors.WHITE, self.tiny_font)
    text_ui:draw(string.format("Player: %.1f, %.1f", player.x, player.y), 8, 22, colors.WHITE, self.tiny_font)

    if current_save_slot then
        text_ui:draw("Current Slot: " .. current_save_slot, 8, 36, colors.WHITE, self.tiny_font)
        text_ui:draw("Press ESC to pause", 8, 50, colors.WHITE, self.tiny_font)
        text_ui:draw("Left Click to Attack", 8, 64, colors.WHITE, self.tiny_font)
        text_ui:draw("Right Click to Parry", 8, 78, colors.WHITE, self.tiny_font)
        text_ui:draw("Space to Dodge/Roll", 8, 92, colors.WHITE, self.tiny_font)
        text_ui:draw("H = Hand Marking Mode", 8, 106, colors.WHITE, self.tiny_font)
        text_ui:draw("P = Mark Anchor Position", 8, 120, colors.WHITE, self.tiny_font)
    else
        text_ui:draw("Press ESC to pause", 8, 36, colors.WHITE, self.tiny_font)
        text_ui:draw("Left Click to Attack", 8, 50, colors.WHITE, self.tiny_font)
        text_ui:draw("Right Click to Parry", 8, 64, colors.WHITE, self.tiny_font)
        text_ui:draw("Space to Dodge/Roll", 8, 78, colors.WHITE, self.tiny_font)
        text_ui:draw("H = Hand Marking Mode", 8, 92, colors.WHITE, self.tiny_font)
        text_ui:draw("P = Mark Anchor Position", 8, 106, colors.WHITE, self.tiny_font)
    end

    local state_text = "State: " .. player.state
    if player.attack_cooldown > 0 then
        state_text = state_text .. string.format(" (CD: %.1f)", player.attack_cooldown)
    end
    if player.dodge_active then
        state_text = state_text .. " [DODGING]"
    end
    local state_y = current_save_slot and 134 or 120
    text_ui:draw(state_text, 8, state_y, colors.WHITE, self.tiny_font)
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
            colors:apply(colors.for_hud_slot_selected_bg)
        else
            colors:apply(colors.for_hud_slot_normal_bg)
        end
        love.graphics.rectangle("fill", x, y, slot_size, slot_size)

        -- Border
        if i == inventory.selected_slot then
            colors:apply(colors.for_hud_cooldown_ready)
            love.graphics.setLineWidth(2)
        else
            colors:apply(colors.for_hud_cooldown_active)
            love.graphics.setLineWidth(1)
        end
        love.graphics.rectangle("line", x, y, slot_size, slot_size)

        -- Item icon (text representation for now)
        local icon_text = "HP"
        -- Use item's color property if available, otherwise default to white
        local icon_color = item.color or {1, 1, 1, 1}
        text_ui:draw(icon_text, x + 10, y + 8, icon_color, self.small_font)

        -- Quantity
        text_ui:draw("x" .. item.quantity, x + 5, y + 30, {1, 1, 1, 1}, self.small_font)

        -- Slot number
        text_ui:draw(tostring(i), x + 5, y + 3, {0.7, 0.7, 0.7, 1}, self.small_font)
    end

    colors:reset()
    love.graphics.setLineWidth(1)
end

return hud

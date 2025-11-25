-- engine/core/debug/render.lua
-- Rendering functions for debug information

local text_ui = require "engine.utils.text"
local helpers = require "engine.core.debug.helpers"

local render = {}

-- Draw debug info panel
function render.drawInfo(debug_state, display, player, current_save_slot, effects_sys, quest_sys)
    if not debug_state.enabled then return end

    -- Check if any debug info is enabled
    local has_any_info = debug_state.show_fps or debug_state.show_player_info or debug_state.show_screen_info or
                         debug_state.show_quest_debug or debug_state.show_effects
    if not has_any_info then return end

    local sw, sh = display:GetScreenDimensions()
    local vw, vh = display:GetVirtualDimensions()
    local scale = display:GetScale()
    local offset_x, offset_y = display:GetOffset()
    local vmx, vmy = display:GetVirtualMousePosition()

    local white = {1, 1, 1, 1}
    local y_start = 70  -- Offset to avoid overlapping HP bar
    local y_offset = y_start + 10

    -- Calculate panel height dynamically
    local line_count = 0
    if debug_state.show_fps then line_count = line_count + 1 end
    if debug_state.show_effects and effects_sys then line_count = line_count + 1 end
    if debug_state.show_player_info and player then line_count = line_count + 5 end
    if debug_state.show_screen_info then
        line_count = line_count + 6
        if display.is_mobile then
            line_count = line_count + 3
        else
            line_count = line_count + 1
        end
    end
    if debug_state.show_quest_debug and quest_sys then
        local quest_info = helpers.getQuestDebugInfo(quest_sys)
        line_count = line_count + #quest_info + 1  -- +1 for header
    end

    local panel_height = line_count * 20 + 20

    -- Draw panel background
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, y_start, 250, panel_height)

    -- F3: FPS
    if debug_state.show_fps then
        text_ui:draw("FPS: " .. love.timer.getFPS(), 10, y_offset, white)
        y_offset = y_offset + 20
    end

    -- F3: Effects (shown with FPS)
    if debug_state.show_effects and effects_sys then
        local effects_count = effects_sys:getCount()
        text_ui:draw("Effects: " .. effects_count, 10, y_offset, white)
        y_offset = y_offset + 20
    end

    -- F4: Player info
    if debug_state.show_player_info and player then
        text_ui:draw(string.format("Pos: %.1f, %.1f", player.x, player.y), 10, y_offset, white)
        y_offset = y_offset + 20
        text_ui:draw("HP: " .. player.health, 10, y_offset, white)
        y_offset = y_offset + 20
        text_ui:draw("State: " .. (player.state or "unknown"), 10, y_offset, white)
        y_offset = y_offset + 20

        if current_save_slot then
            text_ui:draw("Slot: " .. current_save_slot, 10, y_offset, white)
            y_offset = y_offset + 20
        end

        if player.game_mode then
            text_ui:draw("Mode: " .. player.game_mode, 10, y_offset, white)
            y_offset = y_offset + 20
        end
    end

    -- F5: Screen info
    if debug_state.show_screen_info then
        text_ui:draw("Screen: " .. sw .. "x" .. sh, 10, y_offset, white)
        y_offset = y_offset + 20
        text_ui:draw("Virtual: " .. vw .. "x" .. vh, 10, y_offset, white)
        y_offset = y_offset + 20
        text_ui:draw("Scale: " .. string.format("%.2f", scale), 10, y_offset, white)
        y_offset = y_offset + 20
        text_ui:draw("Offset: " .. string.format("%.1f, %.1f", offset_x, offset_y), 10, y_offset, white)
        y_offset = y_offset + 20
        text_ui:draw("Mode: " .. display.scale_mode, 10, y_offset, white)
        y_offset = y_offset + 20
        text_ui:draw("VMouse: " .. string.format("%.1f, %.1f", vmx, vmy), 10, y_offset, white)
        y_offset = y_offset + 20

        -- Platform-specific info
        if display.is_mobile then
            text_ui:draw("Platform: " .. love.system.getOS(), 10, y_offset, white)
            y_offset = y_offset + 20
            text_ui:draw("DPI: " .. string.format("%.2f", display.dpi_scale), 10, y_offset, white)
            y_offset = y_offset + 20

            local touches = display:GetAllTouches()
            text_ui:draw("Touches: " .. #touches, 10, y_offset, white)
            y_offset = y_offset + 20
        else
            text_ui:draw("F11: Fullscreen", 10, y_offset, white)
            y_offset = y_offset + 20
        end
    end

    -- F6: Quest debug
    if debug_state.show_quest_debug and quest_sys then
        local quest_info = helpers.getQuestDebugInfo(quest_sys)
        text_ui:draw("=== QUESTS ===", 10, y_offset, {1, 1, 0, 1})
        y_offset = y_offset + 20
        for _, line in ipairs(quest_info) do
            text_ui:draw(line, 10, y_offset, white)
            y_offset = y_offset + 20
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw help screen
function render.drawHelp(debug_state, x, y)
    if not debug_state.enabled then return end

    if not debug_state.help_font then
        debug_state.help_font = love.graphics.newFont(12)
    end
    love.graphics.setFont(debug_state.help_font)

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 5, y - 5, 260, 198)

    text_ui:draw("DEBUG CONTROLS:", x, y, {1, 1, 0, 1})
    local white = {1, 1, 1, 1}
    text_ui:draw("F1: Toggle Debug Mode", x, y + 18, white)
    text_ui:draw("F2: Colliders/Grid", x, y + 33, white)
    text_ui:draw("F3: FPS/Effects", x, y + 48, white)
    text_ui:draw("F4: Player Info", x, y + 63, white)
    text_ui:draw("F5: Screen Info", x, y + 78, white)
    text_ui:draw("F6: Quest Debug", x, y + 93, white)
    text_ui:draw("F7: Hot Reload", x, y + 108, white)
    text_ui:draw("F8: Test Effects", x, y + 123, white)
    text_ui:draw("F9: Virtual Mouse", x, y + 138, white)
    text_ui:draw("F10: Virtual Gamepad", x, y + 153, white)
    text_ui:draw("H: Hand Marking", x, y + 168, white)
end

return render

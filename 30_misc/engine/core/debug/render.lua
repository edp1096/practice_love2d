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
    if debug_state.show_player_info and player then
        line_count = line_count + 5
        if player.on_stair then
            line_count = line_count + 1
        end
    end
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

        -- Show stair info if on stairs
        if player.on_stair then
            text_ui:draw("Stair: " .. (player.on_stair.hill_direction or "?"), 10, y_offset, {1, 0.5, 0, 1})
            y_offset = y_offset + 20
        end

        -- Show owned vehicles
        local entity_registry = require "engine.core.entity_registry"
        local owned = entity_registry:getOwnedVehicles()
        if #owned > 0 then
            text_ui:draw("Vehicles: " .. table.concat(owned, ", "), 10, y_offset, {0.5, 1, 0.5, 1})
            y_offset = y_offset + 20
        end

        -- Show boarded vehicle
        if player.is_boarded and player.boarded_vehicle then
            text_ui:draw("Riding: " .. (player.boarded_vehicle.type or "?"), 10, y_offset, {0.5, 1, 1, 1})
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

-- Draw player collider debug visualization (F2)
function render.drawPlayerColliders(debug_state, player)
    if not debug_state.show_colliders or not player.collider then return end

    -- Main collider (green)
    love.graphics.setColor(0, 1, 0, 0.3)
    love.graphics.rectangle("fill", player.x - player.collider_width / 2, player.y - player.collider_height / 2, player.collider_width, player.collider_height)
    love.graphics.setColor(1, 1, 1, 1)

    -- Portal check box (blue) - bottom quarter for natural portal entrance
    local portal_w = player.collider_width
    local portal_h = player.collider_height / 4
    local quarter_offset = player.collider_height / 4
    local portal_x = player.x - portal_w / 2
    local portal_y = player.y + quarter_offset

    love.graphics.setColor(0, 0.5, 1, 0.3)
    love.graphics.rectangle("fill", portal_x, portal_y, portal_w, portal_h)
    love.graphics.setColor(0, 0.8, 1, 1)
    love.graphics.rectangle("line", portal_x, portal_y, portal_w, portal_h)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw stairs debug info in HUD (F2)
function render.drawStairsInfo(debug_state, world, player, vh)
    if not debug_state.show_colliders or not world or not world.stairs then return end

    local stairs_count = #world.stairs
    local on_stair = player.on_stair
    local stair_info = on_stair and on_stair.hill_direction or "none"
    text_ui:draw(string.format("Stairs: %d, On: %s", stairs_count, stair_info),
        12, vh - 80, {0.8, 0.4, 0, 0.8})
end

-- Draw raycast debug visualization (F2, inside camera transform)
function render.drawRaycast(debug_state, player)
    if not debug_state.show_colliders then return end
    if not player or not player._debug_raycast then return end

    local rc = player._debug_raycast
    love.graphics.setLineWidth(2)

    -- Draw raycast line (yellow)
    love.graphics.setColor(1, 1, 0, 0.8)
    love.graphics.line(rc.start_x, rc.start_y, rc.start_x, rc.end_y)

    -- Start point (small yellow circle)
    love.graphics.circle("fill", rc.start_x, rc.start_y, 3)

    -- Hit point or end point
    if rc.hit_y then
        -- Hit detected (red circle)
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.circle("fill", rc.start_x, rc.hit_y, 5)
        -- Hit Y value label
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(string.format("%.0f", rc.hit_y), rc.start_x + 8, rc.hit_y - 8)
    else
        -- No hit (gray circle at end)
        love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
        love.graphics.circle("fill", rc.start_x, rc.end_y, 3)
    end

    -- Draw shadow position (green circle at ground_y)
    if player.ground_y then
        love.graphics.setColor(0, 1, 0, 0.8)
        love.graphics.circle("line", player.x, player.ground_y, 8)
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

return render

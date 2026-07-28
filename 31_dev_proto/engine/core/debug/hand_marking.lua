-- engine/core/debug/hand_marking.lua
-- Hand marking mode for calibrating weapon hand positions

local helpers = require "engine.core.debug.helpers"

local hand_marking = {}

-- Toggle hand marking mode
function hand_marking.toggle(debug_state, player)
    debug_state.hand_marking_active = not debug_state.hand_marking_active
    if debug_state.hand_marking_active then
        debug_state.manual_frame = 1
        dprint("=== HAND MARKING MODE ENABLED ===")
        dprint("Animation PAUSED")
        dprint("PgUp/PgDn: Previous/Next frame")
        dprint("P: Mark hand position (saves position + angle)")
        local anim_name = player.current_anim_name or "idle_right"
        dprint("Current animation: " .. anim_name)
        dprint("Current frame: " .. debug_state.manual_frame)
    else
        dprint("=== HAND MARKING MODE DISABLED ===")
    end
end

-- Next frame
function hand_marking.nextFrame(debug_state, player)
    if not debug_state.hand_marking_active then return end

    local anim_name = player.current_anim_name or "idle_right"
    local frame_count = helpers.getFrameCount(anim_name)
    debug_state.manual_frame = debug_state.manual_frame + 1
    if debug_state.manual_frame > frame_count then
        debug_state.manual_frame = 1
    end
    dprint(anim_name .. " Frame: " .. debug_state.manual_frame .. " / " .. frame_count)
end

-- Previous frame
function hand_marking.previousFrame(debug_state, player)
    if not debug_state.hand_marking_active then return end

    local anim_name = player.current_anim_name or "idle_right"
    local frame_count = helpers.getFrameCount(anim_name)
    debug_state.manual_frame = debug_state.manual_frame - 1
    if debug_state.manual_frame < 1 then
        debug_state.manual_frame = frame_count
    end
    dprint(anim_name .. " Frame: " .. debug_state.manual_frame .. " / " .. frame_count)
end

-- Mark hand position at mouse cursor
function hand_marking.markPosition(debug_state, player, world_x, world_y)
    if not debug_state.hand_marking_active then return end

    local relative_x = world_x - player.x
    local relative_y = world_y - player.y

    local sprite_x = math.floor(relative_x / 3)
    local sprite_y = math.floor(relative_y / 3)

    local anim_name = player.current_anim_name or "idle_right"
    local frame_index = debug_state.manual_frame
    local weapon_angle = player.weapon and player.weapon.angle or 0

    if not debug_state.actual_hand_positions[anim_name] then
        debug_state.actual_hand_positions[anim_name] = {}
    end
    debug_state.actual_hand_positions[anim_name][frame_index] = {
        x = sprite_x,
        y = sprite_y,
        angle = weapon_angle
    }

    local angle_str = helpers.formatAngle(weapon_angle)

    dprint(string.format("MARKED: %s[%d] = {x = %d, y = %d, angle = %s},",
        anim_name, frame_index, sprite_x, sprite_y, angle_str))

    local frame_count = helpers.getFrameCount(anim_name)
    local marked_count = 0
    for _ in pairs(debug_state.actual_hand_positions[anim_name]) do
        marked_count = marked_count + 1
    end

    if marked_count == frame_count then
        dprint("=== COMPLETE " .. anim_name .. " ===")
        dprint(anim_name .. " = {")
        for i = 1, frame_count do
            local pos = debug_state.actual_hand_positions[anim_name][i]
            if pos then
                local angle_str = helpers.formatAngle(pos.angle)
                dprint(string.format("    {x = %d, y = %d, angle = %s},",
                    pos.x, pos.y, angle_str))
            end
        end
        dprint("},")
    end
end

-- Draw hand marker on screen
function hand_marking.drawMarkers(debug_state, player, text_ui)
    if not debug_state.enabled then return end

    local anim_name = player.current_anim_name or "idle_right"
    local frame_index = debug_state.hand_marking_active and debug_state.manual_frame or (player.anim and math.floor(player.anim.position) or 1)

    if debug_state.actual_hand_positions[anim_name] and debug_state.actual_hand_positions[anim_name][frame_index] then
        local pos = debug_state.actual_hand_positions[anim_name][frame_index]
        local world_x = player.x + (pos.x * 3)
        local world_y = player.y + (pos.y * 3)

        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.circle("fill", world_x, world_y, 6)
        love.graphics.setColor(1, 0, 0, 0.5)
        love.graphics.circle("line", world_x, world_y, 12)

        text_ui:draw("ACTUAL", world_x - 20, world_y - 25, {1, 1, 1, 1})
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return hand_marking

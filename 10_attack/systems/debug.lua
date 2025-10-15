-- systems/debug.lua
-- Debug system with hand marking functionality

local debug = {}

debug.debug_mode = false
debug.show_fps = false
debug.show_colliders = false

-- Hand marking system
debug.hand_marking_active = false
debug.manual_frame = 1
debug.actual_hand_positions = {}

function debug:toggle_debug()
    self.debug_mode = not self.debug_mode
    self.show_fps = self.debug_mode
    self.show_colliders = self.debug_mode
end

function debug:toggle_hand_marking(player)
    self.hand_marking_active = not self.hand_marking_active
    if self.hand_marking_active then
        self.manual_frame = 1
        print("=== HAND MARKING MODE ENABLED ===")
        print("Animation PAUSED")
        print("PgUp/PgDown: Previous/Next frame")
        print("P: Mark hand position")
        print("Ctrl+P: Mark weapon anchor")
        print("Current animation: " .. (player.current_anim_name or "unknown"))
        print("Current frame: " .. self.manual_frame)
    else
        print("=== HAND MARKING MODE DISABLED ===")
    end
end

function debug:next_frame(player)
    if not self.hand_marking_active then return end

    local frame_count = self:get_frame_count(player.current_anim_name)
    self.manual_frame = self.manual_frame + 1
    if self.manual_frame > frame_count then
        self.manual_frame = 1
    end
    print(player.current_anim_name .. " Frame: " .. self.manual_frame .. " / " .. frame_count)
end

function debug:prev_frame(player)
    if not self.hand_marking_active then return end

    local frame_count = self:get_frame_count(player.current_anim_name)
    self.manual_frame = self.manual_frame - 1
    if self.manual_frame < 1 then
        self.manual_frame = frame_count
    end
    print(player.current_anim_name .. " Frame: " .. self.manual_frame .. " / " .. frame_count)
end

function debug:mark_hand_position(player, world_x, world_y)
    if not self.hand_marking_active then return end

    local relative_x = world_x - player.x
    local relative_y = world_y - player.y

    local sprite_x = math.floor(relative_x / 3)
    local sprite_y = math.floor(relative_y / 3)

    local anim_name = player.current_anim_name or "idle_right"
    local frame_index = self.manual_frame
    local weapon_angle = player.weapon.angle

    if not self.actual_hand_positions[anim_name] then
        self.actual_hand_positions[anim_name] = {}
    end
    self.actual_hand_positions[anim_name][frame_index] = {
        x = sprite_x,
        y = sprite_y,
        angle = weapon_angle
    }

    local angle_str = self:format_angle(weapon_angle)

    print(string.format("MARKED: %s[%d] = {x = %d, y = %d, angle = %s},",
        anim_name, frame_index, sprite_x, sprite_y, angle_str))

    local frame_count = self:get_frame_count(anim_name)
    local marked_count = 0
    for _ in pairs(self.actual_hand_positions[anim_name]) do
        marked_count = marked_count + 1
    end

    if marked_count == frame_count then
        print("=== COMPLETE " .. anim_name .. " ===")
        print(anim_name .. " = {")
        for i = 1, frame_count do
            local pos = self.actual_hand_positions[anim_name][i]
            if pos then
                local angle_str = self:format_angle(pos.angle)
                print(string.format("    {x = %d, y = %d, angle = %s},",
                    pos.x, pos.y, angle_str))
            end
        end
        print("},")
    end
end

function debug:format_angle(angle)
    if not angle then return "nil" end

    local pi = math.pi
    local tolerance = 0.01

    local angles = {
        { value = 0,           str = "0" },
        { value = pi / 6,      str = "math.pi / 6" },
        { value = pi / 4,      str = "math.pi / 4" },
        { value = pi / 3,      str = "math.pi / 3" },
        { value = pi / 2,      str = "math.pi / 2" },
        { value = pi * 2 / 3,  str = "math.pi * 2 / 3" },
        { value = pi * 3 / 4,  str = "math.pi * 3 / 4" },
        { value = pi * 5 / 6,  str = "math.pi * 5 / 6" },
        { value = pi,          str = "math.pi" },
        { value = -pi / 6,     str = "-math.pi / 6" },
        { value = -pi / 4,     str = "-math.pi / 4" },
        { value = -pi / 3,     str = "-math.pi / 3" },
        { value = -pi / 2,     str = "-math.pi / 2" },
        { value = pi * 5 / 12, str = "math.pi * 5 / 12" },
        { value = pi * 7 / 12, str = "math.pi * 7 / 12" },
    }

    for _, entry in ipairs(angles) do
        if math.abs(angle - entry.value) < tolerance then
            return entry.str
        end
    end

    return string.format("%.4f", angle)
end

function debug:get_frame_count(anim_name)
    local counts = {
        idle_right = 4,
        idle_left = 4,
        idle_up = 4,
        idle_down = 4,
        walk_right = 6,
        walk_left = 6,
        walk_up = 4,
        walk_down = 4,
        attack_right = 4,
        attack_left = 4,
        attack_up = 4,
        attack_down = 4
    }
    return counts[anim_name] or 4
end

function debug:draw_hand_markers(player)
    if not self.debug_mode then return end

    local anim_name = player.current_anim_name or "idle_right"
    local frame_index = self.hand_marking_active and self.manual_frame or (player.anim and math.floor(player.anim.position) or 1)

    if self.actual_hand_positions[anim_name] and self.actual_hand_positions[anim_name][frame_index] then
        local pos = self.actual_hand_positions[anim_name][frame_index]
        local world_x = player.x + (pos.x * 3)
        local world_y = player.y + (pos.y * 3)

        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.circle("fill", world_x, world_y, 6)
        love.graphics.setColor(1, 0, 0, 0.5)
        love.graphics.circle("line", world_x, world_y, 12)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("ACTUAL", world_x - 20, world_y - 25)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function debug:is_hand_marking_active()
    return self.hand_marking_active
end

return debug

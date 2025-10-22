-- systems/debug.lua
-- Unified debug system: gameplay, rendering, and advanced features

local debug = {}

-- === Master Control ===
debug.enabled = false

-- === Gameplay Debug ===
debug.show_fps = false
debug.show_colliders = false
debug.show_player_info = false
debug.show_ai_state = false

-- === Rendering/Screen Debug ===
debug.show_screen_info = false
debug.show_virtual_mouse = false
debug.show_bounds = false

-- === Effects Debug ===
debug.show_effects = false

-- === NPC Debug ===
debug.show_npcs = false

-- === Advanced Features ===
debug.hand_marking_active = false
debug.manual_frame = 1
debug.actual_hand_positions = {}

-- Legacy compatibility (for modules that check debug.debug_mode)
function debug:updateLegacyFlag()
    self.debug_mode = self.enabled
end

-- === Master Toggle ===
function debug:toggle()
    self.enabled = not self.enabled

    if self.enabled then
        -- Enable common debug features
        self.show_fps = true
        self.show_colliders = true
        self.show_player_info = true
        print("=== DEBUG MODE ENABLED ===")
        print("F1: Screen Info | F2: Virtual Mouse | F4: Effects | F5: Test Effects")
        print("H: Hand Marking | P: Mark Position | PgUp/PgDn: Frame Nav")
    else
        -- Disable all debug features
        self.show_fps = false
        self.show_colliders = false
        self.show_player_info = false
        self.show_screen_info = false
        self.show_virtual_mouse = false
        self.show_effects = false
        self.show_ai_state = false
        self.show_npcs = false
        self.show_bounds = false
        print("=== DEBUG MODE DISABLED ===")
    end

    self:updateLegacyFlag()
end

-- === Layer-Specific Toggles ===
function debug:toggleLayer(layer)
    if not self.enabled then
        print("Enable debug mode first (F3)")
        return
    end

    if layer == "screen" then
        self.show_screen_info = not self.show_screen_info
        print("Screen debug: " .. tostring(self.show_screen_info))
    elseif layer == "mouse" then
        self.show_virtual_mouse = not self.show_virtual_mouse
        print("Virtual mouse: " .. tostring(self.show_virtual_mouse))
    elseif layer == "effects" then
        self.show_effects = not self.show_effects
        print("Effects debug: " .. tostring(self.show_effects))
    elseif layer == "ai" then
        self.show_ai_state = not self.show_ai_state
        print("AI debug: " .. tostring(self.show_ai_state))
    elseif layer == "npcs" then
        self.show_npcs = not self.show_npcs
        print("NPC debug: " .. tostring(self.show_npcs))
    end
end

-- === Unified Input Handler ===
function debug:handleInput(key, context)
    -- context = { player, world, camera } (optional)
    context = context or {}

    if key == "f3" then
        -- Master toggle (works everywhere)
        self:toggle()
    elseif not self.enabled then
        -- Debug mode is off, ignore other debug keys
        return

        -- === Layer Toggles (debug mode must be on) ===
    elseif key == "f1" then
        self:toggleLayer("screen")
    elseif key == "f2" then
        self:toggleLayer("mouse")
    elseif key == "f4" then
        self:toggleLayer("effects")
    elseif key == "f6" then
        self:toggleLayer("ai")
    elseif key == "f7" then
        self:toggleLayer("npcs")

        -- === Test Functions ===
    elseif key == "f5" and context.camera then
        -- Test effects at mouse position
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = context.camera:worldCoords(mouse_x, mouse_y)
        local effects = require "systems.effects"
        effects:test(world_x, world_y)

        -- === Hand Marking Mode ===
    elseif key == "h" and context.player then
        self:ToggleHandMarking(context.player)
    elseif key == "p" and self.hand_marking_active and context.player and context.camera then
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = context.camera:worldCoords(mouse_x, mouse_y)
        self:MarkHandPosition(context.player, world_x, world_y)
    elseif key == "pageup" and self.hand_marking_active and context.player then
        self:PreviousFrame(context.player)
    elseif key == "pagedown" and self.hand_marking_active and context.player then
        self:NextFrame(context.player)
    end
end

-- === Hand Marking Functions (unchanged) ===
function debug:ToggleHandMarking(player)
    self.hand_marking_active = not self.hand_marking_active
    if self.hand_marking_active then
        self.manual_frame = 1
        print("=== HAND MARKING MODE ENABLED ===")
        print("Animation PAUSED")
        print("PgUp/PgDn: Previous/Next frame")
        print("P: Mark hand position")
        print("Ctrl+P: Mark weapon anchor")
        local anim_name = player.current_anim_name or "idle_right"
        print("Current animation: " .. anim_name)
        print("Current frame: " .. self.manual_frame)
    else
        print("=== HAND MARKING MODE DISABLED ===")
    end
end

function debug:NextFrame(player)
    if not self.hand_marking_active then return end

    local anim_name = player.current_anim_name or "idle_right"
    local frame_count = self:getFrameCount(anim_name)
    self.manual_frame = self.manual_frame + 1
    if self.manual_frame > frame_count then
        self.manual_frame = 1
    end
    print(anim_name .. " Frame: " .. self.manual_frame .. " / " .. frame_count)
end

function debug:PreviousFrame(player)
    if not self.hand_marking_active then return end

    local anim_name = player.current_anim_name or "idle_right"
    local frame_count = self:getFrameCount(anim_name)
    self.manual_frame = self.manual_frame - 1
    if self.manual_frame < 1 then
        self.manual_frame = frame_count
    end
    print(anim_name .. " Frame: " .. self.manual_frame .. " / " .. frame_count)
end

function debug:MarkHandPosition(player, world_x, world_y)
    if not self.hand_marking_active then return end

    local relative_x = world_x - player.x
    local relative_y = world_y - player.y

    local sprite_x = math.floor(relative_x / 3)
    local sprite_y = math.floor(relative_y / 3)

    local anim_name = player.current_anim_name or "idle_right"
    local frame_index = self.manual_frame
    local weapon_angle = player.weapon and player.weapon.angle or 0

    if not self.actual_hand_positions[anim_name] then
        self.actual_hand_positions[anim_name] = {}
    end
    self.actual_hand_positions[anim_name][frame_index] = {
        x = sprite_x,
        y = sprite_y,
        angle = weapon_angle
    }

    local angle_str = self:formatAngle(weapon_angle)

    print(string.format("MARKED: %s[%d] = {x = %d, y = %d, angle = %s},",
        anim_name, frame_index, sprite_x, sprite_y, angle_str))

    local frame_count = self:getFrameCount(anim_name)
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
                local angle_str = self:formatAngle(pos.angle)
                print(string.format("    {x = %d, y = %d, angle = %s},",
                    pos.x, pos.y, angle_str))
            end
        end
        print("},")
    end
end

function debug:formatAngle(angle)
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

function debug:getFrameCount(anim_name)
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

function debug:DrawHandMarkers(player)
    if not self.enabled then return end

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

function debug:IsHandMarkingActive()
    return self.hand_marking_active
end

-- === Help Display ===
function debug:drawHelp(x, y)
    if not self.enabled then return end

    local help_font = love.graphics.newFont(12)
    love.graphics.setFont(help_font)

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 5, y - 5, 240, 140)

    love.graphics.setColor(1, 1, 0, 1)
    love.graphics.print("DEBUG CONTROLS:", x, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("F3: Toggle Debug", x, y + 18)
    love.graphics.print("F1: Screen Info", x, y + 33)
    love.graphics.print("F2: Virtual Mouse", x, y + 48)
    love.graphics.print("F4: Effects Debug", x, y + 63)
    love.graphics.print("F5: Test Effects", x, y + 78)
    love.graphics.print("F6: AI State", x, y + 93)
    love.graphics.print("F7: NPC Debug", x, y + 108)
    love.graphics.print("H: Hand Marking", x, y + 123)
end

-- Initialize legacy flag
debug:updateLegacyFlag()

return debug

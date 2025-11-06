-- engine/debug.lua
-- Unified debug system: gameplay, rendering, and advanced features

local debug = {}

-- Lazy-load effects system (to avoid circular dependency)
local effects = nil
local function get_effects()
    if not effects then
        effects = require "engine.effects"
        -- Set debug reference in effects
        effects.debug = debug
    end
    return effects
end

-- === Master Control ===
debug.enabled = false

-- === Gameplay Debug ===
debug.show_fps = false
debug.show_colliders = false
debug.show_player_info = false

-- === Rendering/Screen Debug ===
debug.show_screen_info = false
debug.show_virtual_mouse = false
debug.show_bounds = false

-- === Effects Debug ===
debug.show_effects = false

-- === Advanced Features ===
debug.hand_marking_active = false
debug.manual_frame = 1
debug.actual_hand_positions = {}

-- === Shared Resources ===
debug.help_font = nil  -- Lazy-loaded help font

-- === Debug Print Function ===
-- Conditional print that only outputs when debug mode is enabled
function debug:dprint(...)
    if self.enabled then
        print(...)
    end
end

-- === Master Toggle ===
function debug:toggle()
    self.enabled = not self.enabled

    if self.enabled then
        -- F1: Enable info window + hitboxes (NO grid)
        self.show_fps = true
        self.show_colliders = false  -- Grid OFF (F2 toggles this separately)
        self.show_player_info = true
        self.show_screen_info = true
        self.show_bounds = true  -- Show hitboxes/collision boxes
        dprint("=== DEBUG MODE ENABLED ===")
        dprint("F2: Toggle Grid | F3: Virtual Mouse | F4: Effects | F5: Test Effects")
        dprint("H: Hand Marking | P: Mark Position | PgUp/PgDn: Frame Nav")
    else
        -- Disable all debug features
        self.show_fps = false
        self.show_colliders = false
        self.show_player_info = false
        self.show_screen_info = false
        self.show_virtual_mouse = false
        self.show_effects = false
        self.show_bounds = false
        dprint("=== DEBUG MODE DISABLED ===")
    end
end

-- === Layer-Specific Toggles ===
function debug:toggleLayer(layer)
    if not self.enabled then
        dprint("Enable debug mode first (F1)")
        return
    end

    if layer == "visualizations" then
        -- F1: Toggle ONLY grid visualization (not hitboxes)
        self.show_colliders = not self.show_colliders
        dprint("Grid visualization: " .. tostring(self.show_colliders))
    elseif layer == "mouse" then
        self.show_virtual_mouse = not self.show_virtual_mouse
        dprint("Virtual mouse: " .. tostring(self.show_virtual_mouse))
    elseif layer == "effects" then
        self.show_effects = not self.show_effects
        dprint("Effects debug: " .. tostring(self.show_effects))
    end
end

-- === Unified Input Handler ===
function debug:handleInput(key, context)
    -- context = { player, world, camera } (optional)
    context = context or {}

    if not self.enabled then
        -- Debug mode is off, ignore other debug keys
        return

        -- === Layer Toggles (debug mode must be on) ===
    elseif key == "f2" then
        self:toggleLayer("visualizations")  -- F2: Toggle grid visualization
    elseif key == "f3" then
        self:toggleLayer("mouse")  -- F3: Toggle virtual mouse
    elseif key == "f4" then
        self:toggleLayer("effects")

        -- === Test Functions ===
    elseif key == "f5" and context.camera then
        -- Test effects at mouse position
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = context.camera:worldCoords(mouse_x, mouse_y)
        get_effects():test(world_x, world_y)

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
        dprint("=== HAND MARKING MODE ENABLED ===")
        dprint("Animation PAUSED")
        dprint("PgUp/PgDn: Previous/Next frame")
        dprint("P: Mark hand position")
        dprint("Ctrl+P: Mark weapon anchor")
        local anim_name = player.current_anim_name or "idle_right"
        dprint("Current animation: " .. anim_name)
        dprint("Current frame: " .. self.manual_frame)
    else
        dprint("=== HAND MARKING MODE DISABLED ===")
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
    dprint(anim_name .. " Frame: " .. self.manual_frame .. " / " .. frame_count)
end

function debug:PreviousFrame(player)
    if not self.hand_marking_active then return end

    local anim_name = player.current_anim_name or "idle_right"
    local frame_count = self:getFrameCount(anim_name)
    self.manual_frame = self.manual_frame - 1
    if self.manual_frame < 1 then
        self.manual_frame = frame_count
    end
    dprint(anim_name .. " Frame: " .. self.manual_frame .. " / " .. frame_count)
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

    dprint(string.format("MARKED: %s[%d] = {x = %d, y = %d, angle = %s},",
        anim_name, frame_index, sprite_x, sprite_y, angle_str))

    local frame_count = self:getFrameCount(anim_name)
    local marked_count = 0
    for _ in pairs(self.actual_hand_positions[anim_name]) do
        marked_count = marked_count + 1
    end

    if marked_count == frame_count then
        dprint("=== COMPLETE " .. anim_name .. " ===")
        dprint(anim_name .. " = {")
        for i = 1, frame_count do
            local pos = self.actual_hand_positions[anim_name][i]
            if pos then
                local angle_str = self:formatAngle(pos.angle)
                dprint(string.format("    {x = %d, y = %d, angle = %s},",
                    pos.x, pos.y, angle_str))
            end
        end
        dprint("},")
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

-- === Debug Info Panel ===
function debug:drawInfo(screen, player, current_save_slot)
    if not self.enabled then return end

    local sw, sh = screen:GetScreenDimensions()
    local vw, vh = screen:GetVirtualDimensions()
    local scale = screen:GetScale()
    local offset_x, offset_y = screen:GetOffset()
    local vmx, vmy = screen:GetVirtualMousePosition()

    -- Get effects and input info (if available)
    local effects_count = 0
    local has_effects = pcall(function()
        local effects = require "engine.effects"
        effects_count = effects:getCount()
    end)

    local gamepad_info = nil
    local has_gamepad = pcall(function()
        local input = require "engine.input"
        if input:hasGamepad() then
            gamepad_info = input:getDebugInfo()
        end
    end)

    -- Calculate panel height based on content
    local base_height = 185
    local mobile_extra = screen.is_mobile and 60 or 0
    local player_extra = player and 120 or 0
    local effects_extra = has_effects and 20 or 0
    local gamepad_extra = gamepad_info and 40 or 0
    local panel_height = base_height + mobile_extra + player_extra + effects_extra + gamepad_extra

    -- Unified debug panel background
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", 0, 0, 250, panel_height)

    love.graphics.setColor(1, 1, 1, 1)

    -- FPS (most important, show first)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)

    -- Player info (if available)
    local y_offset = 30
    if player then
        love.graphics.print(string.format("Player: %.1f, %.1f", player.x, player.y), 10, y_offset)
        y_offset = y_offset + 20
        love.graphics.print("Health: " .. player.health, 10, y_offset)
        y_offset = y_offset + 20
        love.graphics.print("State: " .. (player.state or "unknown"), 10, y_offset)
        y_offset = y_offset + 20

        if current_save_slot then
            love.graphics.print("Current Slot: " .. current_save_slot, 10, y_offset)
            y_offset = y_offset + 20
        end

        if player.game_mode then
            love.graphics.print("Mode: " .. player.game_mode, 10, y_offset)
            y_offset = y_offset + 20
        end

        y_offset = y_offset + 10  -- Extra spacing before screen info
    end

    -- Screen/Scale info
    love.graphics.print("Screen: " .. sw .. "x" .. sh, 10, y_offset)
    y_offset = y_offset + 20
    love.graphics.print("Virtual: " .. vw .. "x" .. vh, 10, y_offset)
    y_offset = y_offset + 20
    love.graphics.print("Scale: " .. string.format("%.2f", scale), 10, y_offset)
    y_offset = y_offset + 20
    love.graphics.print("Offset: " .. string.format("%.1f", offset_x) .. ", " .. string.format("%.1f", offset_y), 10, y_offset)
    y_offset = y_offset + 20
    love.graphics.print("Mode: " .. screen.scale_mode, 10, y_offset)
    y_offset = y_offset + 20
    love.graphics.print("Virtual Mouse: " .. string.format("%.1f", vmx) .. ", " .. string.format("%.1f", vmy), 10, y_offset)
    y_offset = y_offset + 20

    -- Platform-specific info
    if screen.is_mobile then
        y_offset = y_offset + 10
        love.graphics.print("Platform: " .. love.system.getOS(), 10, y_offset)
        y_offset = y_offset + 20
        love.graphics.print("DPI Scale: " .. string.format("%.2f", screen.dpi_scale), 10, y_offset)
        y_offset = y_offset + 20

        local touches = screen:GetAllTouches()
        love.graphics.print("Touches: " .. #touches, 10, y_offset)
        y_offset = y_offset + 20
    else
        y_offset = y_offset + 10
        love.graphics.print("F11: Toggle Fullscreen", 10, y_offset)
        y_offset = y_offset + 20
    end

    -- Effects info (if available)
    if has_effects then
        love.graphics.print("Active Effects: " .. effects_count, 10, y_offset)
        y_offset = y_offset + 20
    end

    -- Gamepad info (if connected)
    if gamepad_info then
        love.graphics.print(gamepad_info, 10, y_offset)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

-- === Help Display ===
function debug:drawHelp(x, y)
    if not self.enabled then return end

    if not self.help_font then
        self.help_font = love.graphics.newFont(12)
    end
    love.graphics.setFont(self.help_font)

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", x - 5, y - 5, 240, 120)

    love.graphics.setColor(1, 1, 0, 1)
    love.graphics.print("DEBUG CONTROLS:", x, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("F1: Toggle Debug", x, y + 18)
    love.graphics.print("F2: Grid, Collider Info", x, y + 33)
    love.graphics.print("F3: Virtual Mouse", x, y + 48)
    love.graphics.print("F4: Effects Debug", x, y + 63)
    love.graphics.print("F5: Test Effects", x, y + 78)
    love.graphics.print("H: Hand Marking", x, y + 93)
end

return debug

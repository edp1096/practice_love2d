-- engine/core/debug/init.lua
-- Unified debug system: gameplay, rendering, and advanced features

local coords = require "engine.core.coords"
local render = require "engine.core.debug.render"
local hand_marking = require "engine.core.debug.hand_marking"
local hotreload = require "engine.core.debug.hotreload"

local debug = {}

-- Lazy-load effects system (to avoid circular dependency)
local effects = nil
local function get_effects()
    if not effects then
        effects = require "engine.systems.effects"
        -- Set debug reference in effects
        effects.debug = debug
    end
    return effects
end

-- === Master Control ===
debug.allowed = false  -- Whether F1-F10 keys are allowed (set from APP_CONFIG.is_debug)
debug.enabled = false  -- Whether debug UI is currently shown (toggled with F1)

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

-- === Quest Debug ===
debug.show_quest_debug = false

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
        -- F1: Only enable debug mode (all features start OFF)
        dprint("=== DEBUG MODE ENABLED ===")
        dprint("F2: Colliders/Grid | F3: FPS/Effects | F4: Player Info | F5: Screen Info")
        dprint("F6: Quest Debug | F7: Hot Reload | F8: Test Effects")
        dprint("F9: Virtual Mouse | F10: Virtual Gamepad")
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
        self.show_quest_debug = false

        -- Reset virtual gamepad debug override
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"
        if virtual_gamepad.debug_override then
            virtual_gamepad.debug_override = false
            virtual_gamepad.visible = false

            -- Disable virtual gamepad on PC (restore original state)
            local os = love.system.getOS()
            if os ~= "Android" and os ~= "iOS" then
                virtual_gamepad.enabled = false
            end

            dprint("Virtual gamepad debug override disabled")
        end

        dprint("=== DEBUG MODE DISABLED ===")
    end
end

-- === Layer-Specific Toggles ===
function debug:toggleLayer(layer)
    if not self.enabled then
        dprint("Enable debug mode first (F1)")
        return
    end

    if layer == "colliders" then
        -- F2: Toggle colliders/grid + bounds
        self.show_colliders = not self.show_colliders
        self.show_bounds = self.show_colliders
        dprint("Colliders/Grid: " .. tostring(self.show_colliders))
    elseif layer == "fps_effects" then
        -- F3: Toggle FPS + Effects
        self.show_fps = not self.show_fps
        self.show_effects = self.show_fps
        dprint("FPS/Effects: " .. tostring(self.show_fps))
    elseif layer == "player_info" then
        -- F4: Toggle player info
        self.show_player_info = not self.show_player_info
        dprint("Player Info: " .. tostring(self.show_player_info))
    elseif layer == "screen_info" then
        -- F5: Toggle screen info
        self.show_screen_info = not self.show_screen_info
        dprint("Screen Info: " .. tostring(self.show_screen_info))
    elseif layer == "quest" then
        -- F6: Toggle quest debug
        self.show_quest_debug = not self.show_quest_debug
        dprint("Quest Debug: " .. tostring(self.show_quest_debug))
    elseif layer == "virtual_mouse" then
        -- F9: Toggle virtual mouse
        self.show_virtual_mouse = not self.show_virtual_mouse
        dprint("Virtual Mouse: " .. tostring(self.show_virtual_mouse))
    elseif layer == "virtual_gamepad" then
        -- F10: Toggle virtual gamepad visibility (PC only, for layout testing)
        local virtual_gamepad = require "engine.core.input.virtual_gamepad"

        -- If not initialized yet (PC), initialize it
        if not virtual_gamepad.display then
            dprint("Initializing virtual gamepad for debug mode...")
            virtual_gamepad:init()
        end

        -- Force enable for debug mode (PC normally has enabled=false)
        if not virtual_gamepad.enabled then
            virtual_gamepad.enabled = true
            -- Calculate positions now that it's enabled
            virtual_gamepad:calculatePositions()
            dprint("Virtual gamepad force enabled for debug mode")
        end

        -- Enable debug override so scenes can't change visibility
        virtual_gamepad.debug_override = true

        -- Toggle visibility
        virtual_gamepad.visible = not virtual_gamepad.visible
        dprint("Virtual Gamepad: " .. tostring(virtual_gamepad.visible))

        if virtual_gamepad.visible then
            dprint("  enabled: " .. tostring(virtual_gamepad.enabled))
            dprint("  display: " .. tostring(virtual_gamepad.display ~= nil))
        end
    end
end

-- === Unified Input Handler ===
function debug:handleInput(key, context)
    -- context = { player, world, camera } (optional)
    context = context or {}

    -- All debug keys only work when allowed (APP_CONFIG.is_debug = true)
    if not self.allowed then
        return
    end

    -- F1: Master toggle (only works if allowed)
    if key == "f1" then
        self:toggle()
        return
    end

    -- All other debug keys require debug mode to be enabled
    if not self.enabled then
        return
    end

    -- === Layer Toggles (debug mode must be on) ===
    if key == "f2" then
        self:toggleLayer("colliders")  -- F2: Toggle colliders/grid
    elseif key == "f3" then
        self:toggleLayer("fps_effects")  -- F3: Toggle FPS + Effects
    elseif key == "f4" then
        self:toggleLayer("player_info")  -- F4: Toggle player info
    elseif key == "f5" then
        self:toggleLayer("screen_info")  -- F5: Toggle screen info
    elseif key == "f6" then
        self:toggleLayer("quest")  -- F6: Toggle quest debug
    elseif key == "f7" and context.player then
        -- F7: Hot reload player + weapon config
        hotreload.reloadPlayerConfig(context.player)
        hotreload.reloadWeaponConfig(context.player)
    elseif key == "f8" and context.camera then
        -- F8: Test effects at mouse position
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = coords:cameraToWorld(mouse_x, mouse_y, context.camera)
        get_effects():test(world_x, world_y)
    elseif key == "f9" then
        self:toggleLayer("virtual_mouse")  -- F9: Toggle virtual mouse
    elseif key == "f10" then
        self:toggleLayer("virtual_gamepad")  -- F10: Toggle virtual gamepad

        -- === Hand Marking Mode ===
    elseif key == "h" and context.player then
        hand_marking.toggle(self, context.player)
    elseif key == "p" and self.hand_marking_active and context.player and context.camera then
        local mouse_x, mouse_y = love.mouse.getPosition()
        local world_x, world_y = coords:cameraToWorld(mouse_x, mouse_y, context.camera)
        hand_marking.markPosition(self, context.player, world_x, world_y)
    elseif key == "pageup" and self.hand_marking_active and context.player then
        hand_marking.previousFrame(self, context.player)
    elseif key == "pagedown" and self.hand_marking_active and context.player then
        hand_marking.nextFrame(self, context.player)
    end
end

-- === Rendering Functions ===
function debug:drawInfo(display, player, current_save_slot, effects_sys, quest_sys)
    render.drawInfo(self, display, player, current_save_slot, effects_sys, quest_sys)
end

function debug:drawHelp(x, y)
    render.drawHelp(self, x, y)
end

function debug:DrawHandMarkers(player)
    local text_ui = require "engine.utils.text"
    hand_marking.drawMarkers(self, player, text_ui)
end

function debug:IsHandMarkingActive()
    return self.hand_marking_active
end

return debug

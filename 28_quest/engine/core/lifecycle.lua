-- engine/lifecycle.lua
-- Application lifecycle management (load, draw, update, resize, quit)
-- Orchestrates engine systems and delegates to scene_control

local lifecycle = {}

-- Dependencies (set from main.lua)
lifecycle.display = nil
lifecycle.input = nil
lifecycle.virtual_gamepad = nil
lifecycle.fonts = nil
lifecycle.scene_control = nil
lifecycle.utils = nil
lifecycle.sound = nil
lifecycle.effects = nil
lifecycle.app_config = nil
lifecycle.is_mobile = false

-- Resize callback registry (for systems to register themselves)
lifecycle.resize_callbacks = {}

-- Register a resize callback (called by systems during initialization)
function lifecycle:registerResizeCallback(name, callback)
    self.resize_callbacks[name] = callback
end

-- === Initialization ===

function lifecycle:initialize(initial_scene)
    -- 1. Initialize display system
    local success, err = pcall(self.display.Initialize, self.display, self.app_config)
    if not success then
        print("ERROR: Display initialization failed: " .. tostring(err))
        -- Fallback initialization
        self.display.screen_wh = { w = 0, h = 0 }
        self.display.render_wh = { w = 960, h = 540 }
        self.display.screen_wh.w, self.display.screen_wh.h = love.graphics.getDimensions()
        self.display.scale = math.min(
            self.display.screen_wh.w / self.display.render_wh.w,
            self.display.screen_wh.h / self.display.render_wh.h
        )
        self.display.offset_x = (self.display.screen_wh.w - self.display.render_wh.w * self.display.scale) / 2
        self.display.offset_y = (self.display.screen_wh.h - self.display.render_wh.h * self.display.scale) / 2
    end

    -- 2. Initialize fonts (input already initialized in main.lua)
    self.fonts:init()

    -- 3. Initialize virtual gamepad (mobile only)
    if self.virtual_gamepad then
        self.virtual_gamepad:init()
        self.input:setVirtualGamepad(self.virtual_gamepad)
    end

    -- 4. Switch to initial scene
    self.scene_control.switch(initial_scene)
end

-- === Update Loop ===

function lifecycle:update(dt)
    -- Update input system
    self.input:update(dt)

    -- Update virtual gamepad (mobile only)
    if self.virtual_gamepad then
        self.virtual_gamepad:update(dt)
    end

    -- Update current scene
    self.scene_control.update(dt)
end

-- === Rendering ===

function lifecycle:draw()
    -- Draw current scene
    self.scene_control.draw()

    -- Draw virtual gamepad overlay (mobile only)
    if self.virtual_gamepad and self.virtual_gamepad.enabled then
        self.virtual_gamepad:draw()
    end

    -- Draw debug visualizations (if debug mode enabled)
    if self.display then
        local debug = require "engine.core.debug"

        -- F2: Grid visualization
        self.display:ShowGridVisualization(debug.show_colliders)

        -- F3: Virtual mouse cursor
        self.display:ShowVirtualMouse(debug.show_virtual_mouse)

        -- F1: Unified debug info window (drawn in virtual coordinates for scaling)
        if debug.enabled then
            self.display:Attach()
            local current_scene = self.scene_control.current
            local player = current_scene and current_scene.player
            local save_slot = current_scene and current_scene.current_save_slot
            local quest_sys = current_scene and current_scene.quest_system
            debug:drawInfo(self.display, player, save_slot, self.effects, quest_sys)
            self.display:Detach()
        end
    end
end

-- === Window Resize ===

function lifecycle:resize(w, h)
    -- Update config
    self.app_config.width = w
    self.app_config.height = h

    -- Save config to file
    pcall(self.utils.SaveConfig, self.utils, self.app_config, self.sound.settings, self.input.settings, nil)

    -- Recalculate display scale
    pcall(self.display.CalculateScale, self.display)

    -- Call all registered resize callbacks (systems register themselves during init)
    for name, callback in pairs(self.resize_callbacks) do
        pcall(callback, w, h)
    end

    -- Notify current scene
    self.scene_control.resize(w, h)

    -- Resize virtual gamepad (mobile only)
    if self.virtual_gamepad then
        self.virtual_gamepad:resize(w, h)
    end
end

-- === Application Quit ===

function lifecycle:quit()
    -- Save window size if not fullscreen
    local current_w, current_h, current_flags = love.window.getMode()
    if not self.is_mobile and not self.display.is_fullscreen then
        self.app_config.width = current_w
        self.app_config.height = current_h
        if current_flags.display then
            self.app_config.monitor = current_flags.display
        end
        self.app_config.monitor = self.app_config.monitor or 1
    end

    -- Save config
    pcall(self.utils.SaveConfig, self.utils, self.app_config, self.sound.settings, self.input.settings, nil)
end

return lifecycle

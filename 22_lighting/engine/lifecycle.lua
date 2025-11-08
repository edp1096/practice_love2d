-- engine/lifecycle.lua
-- Application lifecycle management (load, draw, update, resize, quit)
-- Orchestrates engine systems and delegates to scene_control

local lifecycle = {}

-- Dependencies (set from main.lua)
lifecycle.locker = nil
lifecycle.display = nil
lifecycle.input = nil
lifecycle.virtual_gamepad = nil
lifecycle.fonts = nil
lifecycle.scene_control = nil
lifecycle.utils = nil
lifecycle.sound = nil
lifecycle.GameConfig = nil
lifecycle.is_mobile = false

-- === Initialization ===

function lifecycle:initialize(initial_scene)
    -- 1. Process locker (single instance check)
    if self.locker then
        local success, err = pcall(self.locker.ProcInit, self.locker)
        if not success then
            dprint("Warning: Locker init failed: " .. tostring(err))
        end
    end

    -- 2. Initialize display system
    local success, err = pcall(self.display.Initialize, self.display, self.GameConfig)
    if not success then
        dprint("ERROR: Display initialization failed: " .. tostring(err))
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

    -- 3. Initialize fonts (input already initialized in main.lua)
    self.fonts:init()

    -- 5. Initialize virtual gamepad (mobile only)
    if self.virtual_gamepad then
        self.virtual_gamepad:init()
        self.input:setVirtualGamepad(self.virtual_gamepad)
        dprint("Virtual gamepad enabled for mobile OS")
    end

    -- 6. Switch to initial scene
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
        local debug = require "engine.debug"

        self.display:ShowGridVisualization() -- F2: Grid visualization

        -- F1: Unified debug info window
        local current_scene = self.scene_control.current
        local player = current_scene and current_scene.player
        local save_slot = current_scene and current_scene.current_save_slot
        debug:drawInfo(self.display, player, save_slot)

        self.display:ShowVirtualMouse() -- F3: Virtual mouse cursor
    end
end

-- === Window Resize ===

function lifecycle:resize(w, h)
    -- Update config
    self.GameConfig.width = w
    self.GameConfig.height = h

    -- Save config to file (use previous_screen_wh to avoid saving fullscreen resolution)
    pcall(self.utils.SaveConfig, self.utils, self.GameConfig, self.sound.settings, self.input.settings, self.display.previous_screen_wh)

    -- Recalculate display scale
    pcall(self.display.CalculateScale, self.display)

    -- Resize lighting system
    local lighting = require "engine.lighting"
    pcall(lighting.resize, lighting, w, h)

    -- Resize screen effects
    local effects = require "engine.effects"
    pcall(effects.screen.resize, effects.screen, w, h)

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
        self.GameConfig.width = current_w
        self.GameConfig.height = current_h
        if current_flags.display then
            self.GameConfig.monitor = current_flags.display
        end
        self.GameConfig.monitor = self.GameConfig.monitor or 1
    end

    -- Save config (use previous_screen_wh to avoid saving fullscreen resolution)
    pcall(self.utils.SaveConfig, self.utils, self.GameConfig, self.sound.settings, self.input.settings, self.display.previous_screen_wh)

    -- Clean up process locker
    if self.locker then
        pcall(self.locker.ProcQuit, self.locker)
    end
end

return lifecycle

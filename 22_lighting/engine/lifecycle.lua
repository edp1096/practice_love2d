-- engine/lifecycle.lua
-- Application lifecycle management (load, draw, update, resize, quit)
-- Orchestrates engine systems and delegates to scene_control

local lifecycle = {}

-- Dependencies (set from main.lua)
lifecycle.locker = nil
lifecycle.screen = nil
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
            print("Warning: Locker init failed: " .. tostring(err))
        end
    end

    -- 2. Initialize screen system
    local success, err = pcall(self.screen.Initialize, self.screen, self.GameConfig)
    if not success then
        print("ERROR: Screen initialization failed: " .. tostring(err))
        -- Fallback initialization
        self.screen.screen_wh = { w = 0, h = 0 }
        self.screen.render_wh = { w = 960, h = 540 }
        self.screen.screen_wh.w, self.screen.screen_wh.h = love.graphics.getDimensions()
        self.screen.scale = math.min(
            self.screen.screen_wh.w / self.screen.render_wh.w,
            self.screen.screen_wh.h / self.screen.render_wh.h
        )
        self.screen.offset_x = (self.screen.screen_wh.w - self.screen.render_wh.w * self.screen.scale) / 2
        self.screen.offset_y = (self.screen.screen_wh.h - self.screen.render_wh.h * self.screen.scale) / 2
    end

    -- 3. Initialize input system
    self.input:init()

    -- 4. Initialize fonts
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
    if self.screen then
        local debug = require "engine.debug"

        self.screen:ShowGridVisualization() -- F2: Grid visualization

        -- F1: Unified debug info window
        local current_scene = self.scene_control.current
        local player = current_scene and current_scene.player
        local save_slot = current_scene and current_scene.current_save_slot
        debug:drawInfo(self.screen, player, save_slot)

        self.screen:ShowVirtualMouse() -- F3: Virtual mouse cursor
    end
end

-- === Window Resize ===

function lifecycle:resize(w, h)
    -- Update config
    self.GameConfig.width = w
    self.GameConfig.height = h

    -- Save config to file
    pcall(self.utils.SaveConfig, self.utils, self.GameConfig, self.sound.settings)

    -- Recalculate screen scale
    pcall(self.screen.CalculateScale, self.screen)

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
    if not self.is_mobile and not self.screen.is_fullscreen then
        self.GameConfig.width = current_w
        self.GameConfig.height = current_h
        self.GameConfig.monitor = current_flags.display
    end

    -- Save config
    pcall(self.utils.SaveConfig, self.utils, self.GameConfig, self.sound.settings)

    -- Clean up process locker
    if self.locker then
        pcall(self.locker.ProcQuit, self.locker)
    end
end

return lifecycle

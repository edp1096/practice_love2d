-- engine/scenes/cutscene.lua
-- Generic intro/cutscene system for level transitions and endings
-- Supports multiple levels and ending scenes via configuration

local cutscene = {}

-- Cutscene configs (injected from game)
cutscene.configs = {}

local scene_control = require "engine.core.scene_control"
local display = require "engine.core.display"
local dialogue = require "engine.ui.dialogue"
local sound = require "engine.core.sound"
local fonts = require "engine.utils.fonts"
local debug = require "engine.core.debug"
local input = require "engine.core.input"

function cutscene:enter(previous, intro_id, target_map, spawn_x, spawn_y, slot, is_new_game)

    -- Hide virtual gamepad during intro/cutscene
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    -- Set scene context for input priority
    input:setSceneContext("menu")

    self.intro_id = intro_id
    self.target_map = target_map
    self.spawn_x = spawn_x
    self.spawn_y = spawn_y
    self.slot = slot -- Optional slot number for new game
    -- Explicit nil check: nil defaults to false, but explicit false/true values are preserved
    if is_new_game == nil then
        is_new_game = false
    end
    self.is_new_game = is_new_game

    -- Mark this intro as viewed (so it won't show again)
    local save = require "engine.core.save"
    save:markIntroAsViewed(intro_id)

    -- Load configuration for this cutscene
    self.config = cutscene.configs[intro_id]

    if not self.config then
        print("Warning: No intro config found for id: " .. tostring(intro_id))
        -- Fallback: skip to target map
        if target_map then
            local gameplay = require "engine.scenes.gameplay"
            scene_control.switch(gameplay, target_map, spawn_x, spawn_y, slot, is_new_game)
        else
            scene_control.switch("menu")
        end
        return
    end

    -- Play intro BGM if specified
    if self.config.bgm then
        sound:playBGM(self.config.bgm, 1.0, true)
    end

    -- Load background image
    if self.config.background then
        local success, result = pcall(function()
            return love.graphics.newImage(self.config.background)
        end)

        if success then
            self.background = result
        else
            print("Warning: Could not load intro background: " .. self.config.background)
            self.background = nil
        end
    else
        self.background = nil
    end

    -- Initialize and show intro messages
    dialogue:initialize(display)
    local speaker = self.config.speaker or ""
    dialogue:showMultiple(speaker, self.config.messages)

    self.dialogue_finished = false
    self.transition_delay = 0
    self.transition_duration = 0.5

    -- Get virtual dimensions
    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    -- Calculate background scaling to fill screen
    if self.background then
        local img_w = self.background:getWidth()
        local img_h = self.background:getHeight()

        local scale_x = vw / img_w
        local scale_y = vh / img_h

        -- Use larger scale to cover entire screen
        self.bg_scale = math.max(scale_x, scale_y)

        -- Center the background
        self.bg_x = (vw - img_w * self.bg_scale) / 2
        self.bg_y = (vh - img_h * self.bg_scale) / 2
    end

    -- Fade-in effect
    self.fade_alpha = 1.0
    self.fade_speed = 2.0

    -- Track gamepad button state for skip charging
    self.skip_button_held = false
end

function cutscene:update(dt)
    dialogue:update(dt)

    -- Fade-in effect
    if self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
    end

    -- Update skip button (use dialogue's skip button)
    if dialogue.skip_button then
        -- Sync gamepad button state to skip button
        if self.skip_button_held then
            dialogue.skip_button.is_pressed = true
        end

        dialogue.skip_button:update(dt)

        -- Check if skip was triggered (fully charged)
        if dialogue.skip_button:isFullyCharged() and not self.dialogue_finished then
            dialogue:clear()
            self.dialogue_finished = true
            self.transition_delay = self.transition_duration
            dialogue.skip_button:reset()
        end
    end

    -- Check if dialogue finished
    if not dialogue:isOpen() and not self.dialogue_finished then
        self.dialogue_finished = true
    end

    -- Transition after delay
    if self.dialogue_finished then
        self.transition_delay = self.transition_delay + dt
        if self.transition_delay >= self.transition_duration then
            -- Check if this is an ending scene
            if self.config.is_ending then
                -- Go to ending (game clear) screen for endings
                scene_control.switch("ending")
            elseif self.target_map then
                -- Go to target map for level transitions
                local gameplay = require "engine.scenes.gameplay"
                scene_control.switch(gameplay, self.target_map, self.spawn_x, self.spawn_y, self.slot, self.is_new_game)
            else
                -- Fallback to menu
                scene_control.switch("menu")
            end
        end
    end
end

function cutscene:draw()
    display:Attach()

    -- Draw background
    if self.background then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(self.background, self.bg_x, self.bg_y, 0, self.bg_scale, self.bg_scale)
    else
        -- Fallback: dark background with gradient
        love.graphics.setColor(0.05, 0.05, 0.1, 1)
        love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)

        -- Add some visual interest with gradient effect
        for i = 0, self.virtual_height, 4 do
            local alpha = (i / self.virtual_height) * 0.3
            love.graphics.setColor(0.1, 0.1, 0.2, alpha)
            love.graphics.rectangle("fill", 0, i, self.virtual_width, 4)
        end
    end

    -- Fade-in overlay
    if self.fade_alpha > 0 then
        love.graphics.setColor(0, 0, 0, self.fade_alpha)
        love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)
    end

    -- Draw dialogue (inside virtual coordinates for proper scaling)
    dialogue:draw()

    display:Detach()
end

function cutscene:keypressed(key)

    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process intro keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if input:wasPressed("menu_select", "keyboard", key) then
        dialogue:handleInput("keyboard")
    end

    -- Start charging skip with menu_back
    if input:wasPressed("menu_back", "keyboard", key) then
        if dialogue.skip_button then
            dialogue.skip_button.is_pressed = true
        end
    end
end

function cutscene:keyreleased(key)

    -- Stop charging skip
    if input:wasPressed("menu_back", "keyboard", key) and dialogue.skip_button then
        dialogue.skip_button.is_pressed = false
        -- Force charge decay when key is released
        if not dialogue.skip_button:isFullyCharged() then
            dialogue.skip_button.charge = 0
        end
    end
end

function cutscene:gamepadpressed(joystick, button)

    if input:wasPressed("menu_select", "gamepad", button) then
        dialogue:handleInput("keyboard")
    end

    -- Start charging skip with menu_back or pause button
    if input:wasPressed("menu_back", "gamepad", button) or input:wasPressed("pause", "gamepad", button) then
        self.skip_button_held = true
    end
end

function cutscene:gamepadreleased(joystick, button)

    -- Stop charging skip
    if input:wasPressed("menu_back", "gamepad", button) or input:wasPressed("pause", "gamepad", button) then
        self.skip_button_held = false
        if dialogue.skip_button then
            dialogue.skip_button.is_pressed = false
            -- Force charge decay when button is released
            if not dialogue.skip_button:isFullyCharged() then
                dialogue.skip_button.charge = 0
            end
        end
    end
end

function cutscene:mousepressed(x, y, button)
    if button == 1 then
        -- Dialogue handles skip button internally
        dialogue:handleInput("mouse", x, y)
    end
end

function cutscene:mousereleased(x, y, button)
    if button == 1 then
        -- Check if skip button was triggered
        if dialogue.skip_button and dialogue.skip_button:touchReleased(0, x, y) then
            -- Skip triggered by button
            if not self.dialogue_finished then
                dialogue:clear()
                self.dialogue_finished = true
                self.transition_delay = self.transition_duration
            end
            return
        end
        -- Otherwise handle dialogue normally
        dialogue:handleInput("mouse_release", x, y)
    end
end

function cutscene:touchpressed(id, x, y, dx, dy, pressure)
    -- Dialogue handles skip button internally
    return dialogue:handleInput("touch", id, x, y)
end

function cutscene:touchreleased(id, x, y, dx, dy, pressure)
    -- Check if skip button was triggered
    if dialogue.skip_button and dialogue.skip_button:touchReleased(id, x, y) then
        -- Skip triggered by button
        if not self.dialogue_finished then
            dialogue:clear()
            self.dialogue_finished = true
            self.transition_delay = self.transition_duration
        end
        return true
    end
    -- Otherwise handle dialogue normally
    return dialogue:handleInput("touch_release", id, x, y)
end

function cutscene:touchmoved(id, x, y, dx, dy, pressure)
    -- Dialogue handles touch move internally
    dialogue:handleInput("touch_move", id, x, y)
end

function cutscene:resize(w, h)
    display:Resize(w, h)

    -- Recalculate virtual dimensions and background scaling
    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    if self.background then
        local img_w = self.background:getWidth()
        local img_h = self.background:getHeight()

        local scale_x = vw / img_w
        local scale_y = vh / img_h

        self.bg_scale = math.max(scale_x, scale_y)
        self.bg_x = (vw - img_w * self.bg_scale) / 2
        self.bg_y = (vh - img_h * self.bg_scale) / 2
    end

    -- Recalculate dialogue button positions
    dialogue:setDisplay(display)
end

return cutscene

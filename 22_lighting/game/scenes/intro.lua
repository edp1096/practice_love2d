-- scenes/intro.lua
-- Generic intro/cutscene system for level transitions and endings
-- Supports multiple levels and ending scenes via configuration

local intro = {}

local scene_control = require "engine.scene_control"
local display = require "engine.display"
local dialogue = require "engine.ui.dialogue"
local intro_configs = require "game.data.intro_configs"
local sound = require "engine.sound"
local fonts = require "engine.utils.fonts"
local debug = require "engine.debug"

function intro:enter(previous, intro_id, target_map, spawn_x, spawn_y, slot)

    -- Hide virtual gamepad during intro/cutscene
    local input = require "engine.input"
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    self.intro_id = intro_id
    self.target_map = target_map
    self.spawn_x = spawn_x
    self.spawn_y = spawn_y
    self.slot = slot -- Optional slot number for new game

    -- Load configuration for this intro
    self.config = intro_configs[intro_id]
    dprint("Config loaded:", self.config ~= nil)

    if not self.config then
        print("Warning: No intro config found for id: " .. tostring(intro_id))
        -- Fallback: skip to target map
        if target_map then
            local play = require "game.scenes.play"
            scene_control.switch(play, target_map, spawn_x, spawn_y, slot)
        else
            scene_control.switch("menu")
        end
        return
    end

    -- Play intro BGM if specified
    if self.config.bgm then
        sound:playBGM(self.config.bgm, 1.0, true)
        dprint("Playing intro BGM:", self.config.bgm)
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
    dialogue:initialize()
    dialogue:setDisplay(display)
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
end

function intro:update(dt)
    dialogue:update(dt)

    -- Fade-in effect
    if self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
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
                -- Go to gameover (game clear) screen for endings
                scene_control.switch("gameover", true)
            elseif self.target_map then
                -- Go to target map for level transitions
                local play = require "game.scenes.play"
                scene_control.switch(play, self.target_map, self.spawn_x, self.spawn_y, self.slot)
            else
                -- Fallback to menu
                scene_control.switch("menu")
            end
        end
    end
end

function intro:draw()
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

    -- Draw skip hint
    if not self.dialogue_finished then
        love.graphics.setFont(fonts.small)
        love.graphics.setColor(0.7, 0.7, 0.7, 0.8)
        love.graphics.printf("Press ESC to skip", 10, self.virtual_height - 20, self.virtual_width - 20, "right")
    end

    display:Detach()
end

function intro:keypressed(key)
    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process intro keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    if key == "return" or key == "space" or key == "z" then
        dialogue:handleInput("keyboard")
    end

    -- Allow skipping intro
    if key == "escape" then
        dialogue:clear()
        self.dialogue_finished = true
        self.transition_delay = self.transition_duration
    end
end

function intro:gamepadpressed(joystick, button)
    if button == "a" or button == "b" then
        dialogue:handleInput("keyboard")
    end

    -- Allow skipping with start button
    if button == "start" then
        dialogue:clear()
        self.dialogue_finished = true
        self.transition_delay = self.transition_duration
    end
end

function intro:mousepressed(x, y, button)
    if button == 1 then
        dialogue:handleInput("mouse", x, y)
    end
end

function intro:mousereleased(x, y, button)
    if button == 1 then
        dialogue:handleInput("mouse_release", x, y)
    end
end

function intro:touchpressed(id, x, y, dx, dy, pressure)
    return dialogue:handleInput("touch", id, x, y)
end

function intro:touchreleased(id, x, y, dx, dy, pressure)
    return dialogue:handleInput("touch_release", id, x, y)
end

function intro:touchmoved(id, x, y, dx, dy, pressure)
    dialogue:handleInput("touch_move", id, x, y)
end

function intro:resize(w, h)
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
end

return intro

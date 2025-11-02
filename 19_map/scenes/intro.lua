-- scenes/intro.lua
-- Generic intro/cutscene system for level transitions and endings
-- Supports multiple levels and ending scenes via configuration

local intro = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local Talkies = require "vendor.talkies"
local intro_configs = require "data.intro_configs"
local sound = require "systems.sound"

function intro:enter(previous, intro_id, target_map, spawn_x, spawn_y, slot)
    print("=== Intro Scene Enter ===")
    print("intro_id:", intro_id)
    print("target_map:", target_map)
    print("spawn_x:", spawn_x)
    print("spawn_y:", spawn_y)
    print("slot:", slot)

    self.intro_id = intro_id
    self.target_map = target_map
    self.spawn_x = spawn_x
    self.spawn_y = spawn_y
    self.slot = slot -- Optional slot number for new game

    -- Load configuration for this intro
    self.config = intro_configs[intro_id]
    print("Config loaded:", self.config ~= nil)

    if not self.config then
        print("Warning: No intro config found for id: " .. tostring(intro_id))
        -- Fallback: skip to target map
        if target_map then
            local play = require "scenes.play"
            scene_control.switch(play, target_map, spawn_x, spawn_y, slot)
        else
            local menu = require "scenes.menu"
            scene_control.switch(menu)
        end
        return
    end

    -- Play intro BGM if specified
    if self.config.bgm then
        sound:playBGM(self.config.bgm, 1.0, true)
        print("Playing intro BGM:", self.config.bgm)
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

    -- Configure Talkies
    Talkies.backgroundColor = { 0, 0, 0, 0.8 }
    Talkies.textSpeed = "fast"
    Talkies.indicatorCharacter = ">"

    -- Show intro messages
    local speaker = self.config.speaker or ""
    Talkies.say(speaker, self.config.messages)

    self.dialogue_finished = false
    self.transition_delay = 0
    self.transition_duration = 0.5

    -- Get virtual dimensions
    local vw, vh = screen:GetVirtualDimensions()
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
    Talkies.update(dt)

    -- Fade-in effect
    if self.fade_alpha > 0 then
        self.fade_alpha = math.max(0, self.fade_alpha - self.fade_speed * dt)
    end

    -- Check if dialogue finished
    if not Talkies.isOpen() and not self.dialogue_finished then
        self.dialogue_finished = true
    end

    -- Transition after delay
    if self.dialogue_finished then
        self.transition_delay = self.transition_delay + dt
        if self.transition_delay >= self.transition_duration then
            -- Check if this is an ending scene
            if self.config.is_ending then
                -- Go to gameover (game clear) screen for endings
                local gameover = require "scenes.gameover"
                scene_control.switch(gameover, true)
            elseif self.target_map then
                -- Go to target map for level transitions
                local play = require "scenes.play"
                scene_control.switch(play, self.target_map, self.spawn_x, self.spawn_y, self.slot)
            else
                -- Fallback to menu
                local menu = require "scenes.menu"
                scene_control.switch(menu)
            end
        end
    end
end

function intro:draw()
    screen:Attach()

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

    -- Draw dialogue
    Talkies.draw()

    -- Draw skip hint
    if not self.dialogue_finished then
        love.graphics.setFont(love.graphics.newFont(12))
        love.graphics.setColor(0.7, 0.7, 0.7, 0.8)
        love.graphics.printf("Press ESC to skip", 10, self.virtual_height - 20, self.virtual_width - 20, "right")
    end

    screen:Detach()
end

function intro:keypressed(key)
    if key == "return" or key == "space" or key == "z" then
        Talkies.onAction()
    end

    -- Allow skipping intro
    if key == "escape" then
        Talkies.clearMessages()
        self.dialogue_finished = true
        self.transition_delay = self.transition_duration
    end
end

function intro:gamepadpressed(joystick, button)
    if button == "a" or button == "b" then
        Talkies.onAction()
    end

    -- Allow skipping with start button
    if button == "start" then
        Talkies.clearMessages()
        self.dialogue_finished = true
        self.transition_delay = self.transition_duration
    end
end

function intro:mousepressed(x, y, button)
    if button == 1 then
        Talkies.onAction()
    end
end

function intro:resize(w, h)
    screen:Resize(w, h)

    -- Recalculate virtual dimensions and background scaling
    local vw, vh = screen:GetVirtualDimensions()
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

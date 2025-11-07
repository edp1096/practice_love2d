-- scenes/gameover.lua
-- Game Over/Clear scene displayed when player dies or wins

local gameover = {}

local scene_control = require "engine.scene_control"
local display = require "engine.display"
local input = require "engine.input"
local sound = require "engine.sound"
local restart_util = require "engine.utils.restart"
local fonts = require "engine.utils.fonts"
local ui_scene = require "engine.ui.menu"
local debug = require "engine.debug"

function gameover:enter(previous, is_clear, ...)
    self.previous = previous
    self.is_clear = is_clear or false

    -- Hide virtual gamepad in gameover menu
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    if self.is_clear then
        self.options = { "Main Menu" }
        -- Play victory BGM from beginning
        sound:playBGM("victory", 1.0, true)
    else
        self.options = { "Restart from Here", "Load Last Save", "Main Menu" }
        -- Play game over BGM from beginning
        sound:playBGM("gameover", 1.0, true)
    end

    self.selected = 1

    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    self.titleFont = fonts.title_large
    self.subtitleFont = fonts.subtitle
    self.optionFont = fonts.option
    self.hintFont = fonts.hint

    self.layout = {
        title_y = vh * 0.24,
        subtitle_y = vh * 0.34,
        options_start_y = vh * 0.49,
        option_spacing = 48,
        hint_y = vh - 28
    }

    self.overlay_alpha = 0
    self.target_alpha = 0.8

    if self.is_clear then
        self.flash_alpha = 1.0
        self.flash_speed = 1.5
        self.flash_color = { 1, 0.8, 0 }
    else
        self.flash_alpha = 1.0
        self.flash_speed = 2.0
        self.flash_color = { 0.8, 0, 0 }
    end

    self.mouse_over = 0
end

function gameover:update(dt)
    if self.overlay_alpha < self.target_alpha then
        self.overlay_alpha = math.min(self.overlay_alpha + dt * 1.5, self.target_alpha)
    end

    if self.flash_alpha > 0 then
        self.flash_alpha = math.max(0, self.flash_alpha - self.flash_speed * dt)
    end

    -- Use scene_ui helper for mouse-over detection
    self.mouse_over = ui_scene.updateMouseOver(self.options, self.layout, self.virtual_width, self.optionFont)
end

function gameover:draw()
    if self.previous and self.previous.draw then
        local success, err = pcall(function() self.previous:draw() end)
        if not success then love.graphics.clear(0, 0, 0, 1) end
    end

    display:Attach()

    love.graphics.setColor(0, 0, 0, self.overlay_alpha)
    love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)

    if self.flash_alpha > 0 then
        love.graphics.setColor(self.flash_color[1], self.flash_color[2], self.flash_color[3], self.flash_alpha * 0.3)
        love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)
    end

    love.graphics.setFont(self.titleFont)
    if self.is_clear then
        love.graphics.setColor(1, 0.9, 0.2, 1)
        local title = "GAME CLEAR!"
        love.graphics.printf(title, 0, self.layout.title_y, self.virtual_width, "center")
    else
        love.graphics.setColor(1, 0.2, 0.2, 1)
        local title = "GAME OVER"
        love.graphics.printf(title, 0, self.layout.title_y, self.virtual_width, "center")
    end

    love.graphics.setFont(self.subtitleFont)
    if self.is_clear then
        love.graphics.setColor(0.9, 0.9, 0.9, 1)
        local subtitle = "Victory!"
        love.graphics.printf(subtitle, 0, self.layout.subtitle_y, self.virtual_width, "center")
    else
        love.graphics.setColor(0.8, 0.8, 0.8, 1)
        local subtitle = "You Have Fallen"
        love.graphics.printf(subtitle, 0, self.layout.subtitle_y, self.virtual_width, "center")
    end

    -- Use scene_ui helper for option rendering
    ui_scene.drawOptions(self.options, self.selected, self.mouse_over, self.optionFont,
        self.layout, self.virtual_width)

    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)

    if input:hasGamepad() then
        love.graphics.printf("D-Pad: Navigate | " ..
            input:getPrompt("menu_select") .. ": Select | " ..
            input:getPrompt("menu_back") .. ": Main Menu",
            0, self.layout.hint_y - 20, self.virtual_width, "center")
        love.graphics.printf("Keyboard: Arrow Keys / WASD | Enter: Select | ESC: Main Menu | Mouse: Hover & Click",
            0, self.layout.hint_y, self.virtual_width, "center")
    else
        love.graphics.printf("Arrow Keys / WASD to navigate, Enter to select | Mouse to hover and click",
            0, self.layout.hint_y, self.virtual_width, "center")
    end

    display:Detach()
end

function gameover:resize(w, h)
    display:Resize(w, h)
    if self.previous and self.previous.resize then self.previous:resize(w, h) end
end

function gameover:keypressed(key)
    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process gameover keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    local nav_result = ui_scene.handleKeyboardNav(key, self.selected, #self.options)

    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    elseif nav_result.action == "back" then
        scene_control.switch("menu")
    end
end

function gameover:gamepadpressed(joystick, button)
    local nav_result = ui_scene.handleGamepadNav(button, self.selected, #self.options)

    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    elseif nav_result.action == "back" then
        scene_control.switch("menu")
    end
end

function gameover:executeOption(option_index)
    if self.is_clear then
        if option_index == 1 then
            scene_control.switch("menu")
        end
    else
        if option_index == 1 then -- Restart from Here
            local play = require "game.scenes.play"
            local map, x, y, slot = restart_util:fromCurrentMap(self.previous)
            scene_control.switch(play, map, x, y, slot)
        elseif option_index == 2 then -- Load Last Save
            local play = require "game.scenes.play"
            local map, x, y, slot = restart_util:fromLastSave(self.previous)
            scene_control.switch(play, map, x, y, slot)
        elseif option_index == 3 then -- Main Menu
            scene_control.switch("menu")
        end
    end
end

function gameover:mousepressed(x, y, button) end

function gameover:mousereleased(x, y, button)
    if button == 1 then
        if self.mouse_over > 0 then
            self.selected = self.mouse_over
            self:executeOption(self.selected)
        end
    end
end

return gameover

-- scenes/menu.lua
-- Main menu with Continue feature, gamepad support, and sound effects

local menu = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local debug = require "systems.debug"
local save_sys = require "systems.save"
local input = require "systems.input"
local sound = require "systems.sound"

function menu:enter(previous, ...)
    self.title = GameConfig.title

    -- Check if save files exist and build menu options dynamically
    local has_saves = save_sys:hasSaveFiles()

    if has_saves then
        self.options = { "Continue", "New Game", "Load Game", "Settings", "Quit" }
    else
        self.options = { "New Game", "Settings", "Quit" }
    end

    self.selected = 1
    self.previous_selected = 1

    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    self.titleFont = love.graphics.newFont(48)
    self.optionFont = love.graphics.newFont(28)
    self.hintFont = love.graphics.newFont(16)

    self.layout = {
        title_y = vh * 0.2,
        options_start_y = vh * 0.42,
        option_spacing = 60,
        hint_y = vh - 40
    }

    self.option_hitboxes = {}
    self.mouse_over = 0
    self.previous_mouse_over = 0

    -- Play menu BGM
    sound:playBGM("menu")
end

function menu:update(dt)
    local vmx, vmy = screen:GetVirtualMousePosition()

    self.previous_mouse_over = self.mouse_over
    self.mouse_over = 0
    love.graphics.setFont(self.optionFont)

    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing
        local text_width = self.optionFont:getWidth(option)
        local text_height = self.optionFont:getHeight()

        local x = (self.virtual_width - text_width) / 2
        local padding = 20

        if vmx >= x - padding and vmx <= x + text_width + padding and
            vmy >= y - padding and vmy <= y + text_height + padding then
            self.mouse_over = i
            break
        end
    end

    -- Play navigate sound when mouse moves to different option
    if self.mouse_over ~= self.previous_mouse_over and self.mouse_over > 0 then
        sound:playSFX("menu", "navigate")
    end
end

function menu:draw()
    love.graphics.clear(0.1, 0.1, 0.15, 1)

    screen:Attach()

    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(self.title, 0, self.layout.title_y, self.virtual_width, "center")

    love.graphics.setFont(self.optionFont)
    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing

        if i == self.selected or i == self.mouse_over then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.printf("> " .. option, 0, y, self.virtual_width, "center")
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.printf(option, 0, y, self.virtual_width, "center")
        end
    end

    -- Show gamepad-specific controls if connected
    local hint_text
    if input:hasGamepad() then
        hint_text = "D-Pad / Analog: Navigate | " .. input:getPrompt("menu_select") .. ": Select | " .. input:getPrompt("menu_back") .. ": Quit\nKeyboard: Arrow Keys / WASD | Enter: Select | Mouse: Hover & Click"
    else
        hint_text = "Arrow Keys / WASD to navigate, Enter to select | Mouse to hover and click"
    end

    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf(hint_text, 0, self.layout.hint_y - 20, self.virtual_width, "center")

    -- Gamepad connection status
    if input:hasGamepad() then
        love.graphics.setColor(0.3, 0.8, 0.3, 1)
        love.graphics.print("Controller: " .. input.joystick_name, 10, 10)
    end

    if debug.enabled then
        debug:drawHelp(self.virtual_width - 250, 10)
    end

    screen:Detach()

    screen:ShowDebugInfo()
    screen:ShowVirtualMouse()
end

function menu:resize(w, h)
    screen:Resize(w, h)
end

function menu:keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif input:wasPressed("menu_up", "keyboard", key) then
        self.previous_selected = self.selected
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.options end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_down", "keyboard", key) then
        self.previous_selected = self.selected
        self.selected = self.selected + 1
        if self.selected > #self.options then self.selected = 1 end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_select", "keyboard", key) then
        -- Play select sound
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    else
        debug:handleInput(key, {})
    end
end

function menu:gamepadpressed(joystick, button)
    if input:wasPressed("menu_up", "gamepad", button) then
        self.previous_selected = self.selected
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.options end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.previous_selected = self.selected
        self.selected = self.selected + 1
        if self.selected > #self.options then self.selected = 1 end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_select", "gamepad", button) then
        -- Play select sound
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    elseif input:wasPressed("menu_back", "gamepad", button) then
        love.event.quit()
    end
end

function menu:executeOption(option_index)
    local option_name = self.options[option_index]

    if option_name == "Continue" then
        -- Load most recent save
        local recent_slot = save_sys:getMostRecentSlot()
        if recent_slot then
            local save_data = save_sys:loadGame(recent_slot)
            if save_data then
                local play = require "scenes.play"
                scene_control.switch(play, save_data.map, save_data.x, save_data.y, recent_slot)
            else
                print("ERROR: Failed to load recent save")
                sound:playSFX("menu", "error")
            end
        else
            print("ERROR: No recent save found")
            sound:playSFX("menu", "error")
        end
    elseif option_name == "New Game" then
        local newgame = require "scenes.newgame"
        scene_control.switch(newgame)
    elseif option_name == "Load Game" then
        local load = require "systems.load"
        scene_control.switch(load)
    elseif option_name == "Settings" then
        local settings = require "scenes.settings"
        scene_control.switch(settings)
    elseif option_name == "Quit" then
        love.event.quit()
    end
end

function menu:mousepressed(x, y, button) end

function menu:mousereleased(x, y, button)
    if button == 1 then
        if self.mouse_over > 0 then
            self.selected = self.mouse_over

            -- Play select sound
            sound:playSFX("menu", "select")
            self:executeOption(self.selected)
        end
    end
end

return menu

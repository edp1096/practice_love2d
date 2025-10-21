-- scenes/menu_refactored.lua
-- Refactored main menu using scene_ui utility (70% code reduction)

local menu = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local debug = require "systems.debug"
local input = require "systems.input"
local save_sys = require "systems.save"
local sound = require "systems.sound"
local scene_ui = require "utils.scene_ui"

function menu:enter(previous, ...)
    self.title = GameConfig.title

    -- Build dynamic options based on save file existence
    local has_saves = save_sys:hasSaveFiles()
    self.options = has_saves and
        { "Continue", "New Game", "Load Game", "Settings", "Quit" } or
        { "New Game", "Settings", "Quit" }

    self.selected = 1
    self.mouse_over = 0
    self.previous_mouse_over = 0

    -- Setup UI (using utility functions)
    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh
    self.fonts = scene_ui.createMenuFonts()
    self.layout = scene_ui.createMenuLayout(vh)

    -- Start menu BGM
    sound:playBGM("menu")
end

function menu:update(dt)
    -- Update mouse-over state
    self.previous_mouse_over = self.mouse_over
    self.mouse_over = scene_ui.updateMouseOver(self.options, self.layout, self.virtual_width, self.fonts.option)

    -- Play navigation sound when hovering over different option
    if self.mouse_over ~= self.previous_mouse_over and self.mouse_over > 0 then
        sound:playSFX("menu", "navigate")
    end
end

function menu:draw()
    love.graphics.clear(0.1, 0.1, 0.15, 1)
    screen:Attach()

    -- Draw title
    scene_ui.drawTitle(self.title, self.fonts.title, self.layout.title_y, self.virtual_width)

    -- Draw options
    scene_ui.drawOptions(self.options, self.selected, self.mouse_over, self.fonts.option,
        self.layout, self.virtual_width)

    -- Draw control hints
    scene_ui.drawControlHints(self.fonts.hint, self.layout, self.virtual_width)

    -- Gamepad connection status
    if input:hasGamepad() then
        love.graphics.setColor(0.3, 0.8, 0.3, 1)
        love.graphics.print("Controller: " .. input.joystick_name, 10, 10)
    end

    -- Debug help
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
        return
    end

    -- Handle navigation using utility
    local nav_result = scene_ui.handleKeyboardNav(key, self.selected, #self.options)

    if type(nav_result) == "number" then
        self.selected = nav_result
    elseif nav_result == "select" then
        self:executeOption(self.selected)
    else
        debug:handleInput(key, {})
    end
end

function menu:gamepadpressed(joystick, button)
    local nav_result = scene_ui.handleGamepadNav(button, self.selected, #self.options)

    if type(nav_result) == "number" then
        self.selected = nav_result
    elseif nav_result == "select" then
        self:executeOption(self.selected)
    elseif nav_result == "back" then
        love.event.quit()
    end
end

function menu:executeOption(option_index)
    local option_name = self.options[option_index]

    if option_name == "Continue" then
        local recent_slot = save_sys:getMostRecentSlot()
        if recent_slot then
            local save_data = save_sys:loadGame(recent_slot)
            if save_data then
                local play = require "scenes.play"
                scene_control.switch(play, save_data.map, save_data.x, save_data.y, recent_slot)
            else
                sound:playSFX("menu", "error")
            end
        else
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
    if button == 1 and self.mouse_over > 0 then
        self.selected = self.mouse_over
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    end
end

return menu

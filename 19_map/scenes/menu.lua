-- scenes/menu.lua

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

    local has_saves = save_sys:hasSaveFiles()
    self.options = has_saves and
        { "Continue", "New Game", "Load Game", "Settings", "Quit" } or
        { "New Game", "Settings", "Quit" }

    self.selected = 1
    self.mouse_over = 0
    self.previous_mouse_over = 0

    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh
    self.fonts = scene_ui.createMenuFonts()
    self.layout = scene_ui.createMenuLayout(vh)

    -- Play menu BGM from beginning
    sound:playBGM("menu", 1.0, true)
end

function menu:update(dt)
    self.previous_mouse_over = self.mouse_over
    self.mouse_over = scene_ui.updateMouseOver(self.options, self.layout, self.virtual_width, self.fonts.option)

    if self.mouse_over ~= self.previous_mouse_over and self.mouse_over > 0 then
        sound:playSFX("menu", "navigate")
    end
end

function menu:draw()
    love.graphics.clear(0.1, 0.1, 0.15, 1)
    screen:Attach()

    scene_ui.drawTitle(self.title, self.fonts.title, self.layout.title_y, self.virtual_width)

    scene_ui.drawOptions(self.options, self.selected, self.mouse_over, self.fonts.option,
        self.layout, self.virtual_width)

    scene_ui.drawControlHints(self.fonts.hint, self.layout, self.virtual_width)

    if input:hasGamepad() then
        love.graphics.setColor(0.3, 0.8, 0.3, 1)
        love.graphics.print("Controller: " .. input.joystick_name, 10, 10)
    end

    if debug.enabled then debug:drawHelp(self.virtual_width - 250, 10) end

    screen:Detach()
    screen:ShowDebugInfo()
    screen:ShowVirtualMouse()
end

function menu:resize(w, h) screen:Resize(w, h) end

function menu:keypressed(key)
    if key == "escape" then
        love.event.quit()
        return
    end

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
        -- Find first empty slot or use slot 1
        local empty_slot = nil
        for i = 1, save_sys.MAX_SLOTS do
            local info = save_sys:getSlotInfo(i)
            if not info.exists then
                empty_slot = i
                break
            end
        end

        local slot = empty_slot or 1
        print("Starting new game in slot " .. slot)

        local play = require "scenes.play"
        scene_control.switch(play, "assets/maps/level1/area1.lua", 400, 250, slot)
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

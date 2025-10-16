-- scenes/menu.lua
-- Main menu with Continue feature

local menu = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local debug = require "systems.debug"
local save_sys = require "systems.save"

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
end

function menu:update(dt)
    local vmx, vmy = screen:GetVirtualMousePosition()

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

    local message = "Arrow Keys / WASD to navigate, Enter to select | Mouse to hover and click"
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf(message, 0, self.layout.hint_y, self.virtual_width, "center")

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
    elseif key == "up" or key == "w" then
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.options end
    elseif key == "down" or key == "s" then
        self.selected = self.selected + 1
        if self.selected > #self.options then self.selected = 1 end
    elseif key == "return" or key == "space" then
        self:executeOption(self.selected)
    else
        debug:handleInput(key, {})
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
            end
        else
            print("ERROR: No recent save found")
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
            self:executeOption(self.selected)
        end
    end
end

return menu

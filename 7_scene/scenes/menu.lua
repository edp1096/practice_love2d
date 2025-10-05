-- scenes/menu.lua
-- Main menu scene

local menu = {}

local scene_control = require "systems.scene_control"

function menu:enter(previous, ...)
    self.title = GameConfig.title
    self.options = { "Start Game", "Options", "Quit" }
    self.selected = 1

    self.titleFont = love.graphics.newFont(48)
    self.optionFont = love.graphics.newFont(28)
    self.hintFont = love.graphics.newFont(16)
end

function menu:update(dt)
    -- Menu animations could go here
end

function menu:draw()
    -- Always reset color state first
    love.graphics.setColor(1, 1, 1, 1)

    -- Background color
    love.graphics.clear(0.1, 0.1, 0.15, 1)

    -- Draw title
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(self.title, 0, 100, love.graphics.getWidth(), "center")

    -- Draw menu options
    love.graphics.setFont(self.optionFont)
    for i, option in ipairs(self.options) do
        local y = 250 + (i - 1) * 60

        if i == self.selected then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.printf("> " .. option, 0, y,
                love.graphics.getWidth(), "center")
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.printf(option, 0, y,
                love.graphics.getWidth(), "center")
        end
    end

    -- Controls hint
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Arrow Keys / WASD to navigate, Enter to select",
        0, love.graphics.getHeight() - 40, love.graphics.getWidth(), "center")
end

function menu:keypressed(key)
    if key == "up" or key == "w" then
        self.selected = self.selected - 1
        if self.selected < 1 then
            self.selected = #self.options
        end
    elseif key == "down" or key == "s" then
        self.selected = self.selected + 1
        if self.selected > #self.options then
            self.selected = 1
        end
    elseif key == "return" or key == "space" then
        if self.selected == 1 then
            -- Start game
            local play = require "scenes.play"
            scene_control.switch(play)
        elseif self.selected == 2 then
            -- Options (not implemented yet)
        elseif self.selected == 3 then
            love.event.quit()
        end
    end
end

return menu

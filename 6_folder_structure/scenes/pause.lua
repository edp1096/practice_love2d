-- scenes/pause.lua
-- Pause menu overlay scene

local pause = {}

local scene_control = require "systems.scene_control"

function pause:enter(previous, ...)
    self.previous = previous
    self.options = { "Resume", "Restart", "Quit to Menu" }
    self.selected = 1

    -- Create semi-transparent overlay
    self.overlay_alpha = 0
    self.target_alpha = 0.7
end

function pause:update(dt)
    -- Fade in overlay
    if self.overlay_alpha < self.target_alpha then
        self.overlay_alpha = math.min(self.overlay_alpha + dt * 2, self.target_alpha)
    end
end

function pause:draw()
    -- Draw previous scene (gameplay) in background
    if self.previous and self.previous.draw then
        self.previous:draw()
    end

    -- Draw dark overlay
    love.graphics.setColor(0, 0, 0, self.overlay_alpha)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

    -- Draw pause menu
    love.graphics.setColor(1, 1, 1, 1)

    local title = "PAUSED"
    local titleFont = love.graphics.newFont(32)
    local optionFont = love.graphics.newFont(24)

    love.graphics.setFont(titleFont)
    love.graphics.printf(title, 0, 100, love.graphics.getWidth(), "center")

    love.graphics.setFont(optionFont)
    for i, option in ipairs(self.options) do
        local y = 200 + (i - 1) * 50

        if i == self.selected then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.printf("> " .. option, 0, y, love.graphics.getWidth(), "center")
        else
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf(option, 0, y, love.graphics.getWidth(), "center")
        end
    end

    -- Draw controls hint
    local message = "Arrow Keys / WASD to navigate, Enter to select, P to resume"
    local hintFont = love.graphics.newFont(14)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.setFont(hintFont)
    love.graphics.printf(message, 0, love.graphics.getHeight() - 30, love.graphics.getWidth(), "center")
end

function pause:keypressed(key)
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
        if self.selected == 1 then     -- Resume
            scene_control.pop()
        elseif self.selected == 2 then -- Restart
            local play = require "scenes.play"
            scene_control.switch(play)
        elseif self.selected == 3 then -- Quit to menu
            local menu = require "scenes.menu"
            scene_control.switch(menu)
        end
    elseif key == "p" or key == "escape" then -- Quick resume
        scene_control.pop()
    end
end

return pause

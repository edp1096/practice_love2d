-- scenes/gameover.lua
-- Game Over/Clear scene displayed when player dies or wins
-- UPDATED: Added game clear mode with different UI and options

local gameover = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"

function gameover:enter(previous, is_clear, ...)
    self.previous = previous
    self.is_clear = is_clear or false

    -- Different options based on clear vs game over
    if self.is_clear then
        self.options = { "Main Menu" }
    else
        self.options = { "Restart", "Main Menu" }
    end

    self.selected = 1

    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    self.titleFont = love.graphics.newFont(48)
    self.subtitleFont = love.graphics.newFont(32)
    self.optionFont = love.graphics.newFont(24)
    self.hintFont = love.graphics.newFont(14)

    self.layout = {
        title_y = vh * 0.25,
        subtitle_y = vh * 0.35,
        options_start_y = vh * 0.50,
        option_spacing = 50,
        hint_y = vh - 30
    }

    self.overlay_alpha = 0
    self.target_alpha = 0.8

    -- Different effects based on clear vs game over
    if self.is_clear then
        -- Gold flash for victory
        self.flash_alpha = 1.0
        self.flash_speed = 1.5
        self.flash_color = { 1, 0.8, 0 } -- Gold
    else
        -- Red flash for defeat
        self.flash_alpha = 1.0
        self.flash_speed = 2.0
        self.flash_color = { 0.8, 0, 0 } -- Red
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

function gameover:draw()
    -- Draw previous scene in background (dimmed)
    if self.previous and self.previous.draw then
        local success, err = pcall(function()
            self.previous:draw()
        end)

        if not success then
            love.graphics.clear(0, 0, 0, 1)
        end
    end

    screen:Attach()

    -- Dark overlay
    love.graphics.setColor(0, 0, 0, self.overlay_alpha)
    love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)

    -- Flash overlay (gold for clear, red for game over)
    if self.flash_alpha > 0 then
        love.graphics.setColor(self.flash_color[1], self.flash_color[2], self.flash_color[3], self.flash_alpha * 0.3)
        love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)
    end

    -- Title
    love.graphics.setFont(self.titleFont)
    if self.is_clear then
        love.graphics.setColor(1, 0.9, 0.2, 1) -- Gold
        local title = "GAME CLEAR!"
        love.graphics.printf(title, 0, self.layout.title_y, self.virtual_width, "center")
    else
        love.graphics.setColor(1, 0.2, 0.2, 1) -- Red
        local title = "GAME OVER"
        love.graphics.printf(title, 0, self.layout.title_y, self.virtual_width, "center")
    end

    -- Subtitle
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

    -- Options
    love.graphics.setFont(self.optionFont)
    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing

        if i == self.selected or i == self.mouse_over then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.printf("> " .. option, 0, y, self.virtual_width, "center")
        else
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf(option, 0, y, self.virtual_width, "center")
        end
    end

    -- Controls hint
    local message = "Arrow Keys / WASD to navigate, Enter to select | Mouse to hover and click"
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf(message, 0, self.layout.hint_y, self.virtual_width, "center")

    screen:Detach()
end

function gameover:resize(w, h)
    screen:Resize(w, h)

    if self.previous and self.previous.resize then
        self.previous:resize(w, h)
    end
end

function gameover:keypressed(key)
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
        self:executeOption(self.selected)
    elseif key == "escape" then
        local menu = require "scenes.menu"
        scene_control.switch(menu)
    end
end

function gameover:executeOption(option_index)
    if self.is_clear then
        -- Clear mode: only "Main Menu"
        if option_index == 1 then
            local menu = require "scenes.menu"
            scene_control.switch(menu)
        end
    else
        -- Game over mode: "Restart" or "Main Menu"
        if option_index == 1 then
            local play = require "scenes.play"
            scene_control.switch(play, "assets/maps/level1/area1.lua", 400, 250)
        elseif option_index == 2 then
            local menu = require "scenes.menu"
            scene_control.switch(menu)
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

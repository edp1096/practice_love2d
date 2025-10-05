-- scenes/menu.lua
-- Main menu scene with aspect ratio support

local menu = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"

function menu:enter(previous, ...)
    self.title = GameConfig.title
    self.options = { "Start Game", "Settings", "Quit" }
    self.selected = 1

    -- Get virtual dimensions (960x540 for 16:9)
    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    -- Create fonts with sizes appropriate for virtual resolution
    self.titleFont = love.graphics.newFont(48)
    self.optionFont = love.graphics.newFont(28)
    self.hintFont = love.graphics.newFont(16)

    -- Layout positions based on virtual resolution
    self.layout = {
        title_y = vh * 0.2,          -- 20% from top
        options_start_y = vh * 0.45, -- 45% from top
        option_spacing = 60,
        hint_y = vh - 40             -- 40 pixels from bottom
    }

    -- Mouse interaction areas
    self.option_hitboxes = {}
    self.mouse_over = 0 -- 0 means no option is hovered
end

function menu:update(dt)
    -- Get virtual mouse position
    local vmx, vmy = screen:GetVirtualMousePosition()

    -- Check if mouse is over any option
    self.mouse_over = 0
    love.graphics.setFont(self.optionFont)

    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing
        local text_width = self.optionFont:getWidth(option)
        local text_height = self.optionFont:getHeight()

        -- Center the hitbox
        local x = (self.virtual_width - text_width) / 2
        local padding = 20

        -- Check if mouse is within option bounds
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

        -- Highlight if selected by keyboard or hovered by mouse
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

    screen:Detach()

    -- Draw debug info if enabled (outside virtual coordinates)
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
        if self.selected == 1 then
            -- Start game
            local play = require "scenes.play"
            scene_control.switch(play)
        elseif self.selected == 2 then
            local settings = require "scenes.settings"
            scene_control.switch(settings)
        elseif self.selected == 3 then
            love.event.quit()
        end
    end
end

function menu:mousepressed(x, y, button)
    if button == 1 then -- Left mouse button
        -- Check if any option was clicked
        if self.mouse_over > 0 then
            self.selected = self.mouse_over

            -- Execute the selected option
            if self.selected == 1 then
                -- Start game
                local play = require "scenes.play"
                scene_control.switch(play)
            elseif self.selected == 2 then
                local settings = require "scenes.settings"
                scene_control.switch(settings)
            elseif self.selected == 3 then
                love.event.quit()
            end
        end
    end
end

return menu

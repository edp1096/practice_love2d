-- scenes/pause.lua
-- Pause menu overlay scene with aspect ratio support, save slot persistence, gamepad support, and sound

local pause = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local input = require "systems.input"
local sound = require "systems.sound"

function pause:enter(previous, ...)
    self.previous = previous
    self.options = { "Resume", "Restart", "Settings", "Quit to Menu" }
    self.selected = 1
    self.previous_selected = 1

    -- Get virtual dimensions (960x540 for 16:9)
    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    -- Create fonts with sizes appropriate for virtual resolution
    self.titleFont = love.graphics.newFont(32)
    self.optionFont = love.graphics.newFont(24)
    self.hintFont = love.graphics.newFont(14)

    -- Layout positions based on virtual resolution (adjusted for 4 options)
    self.layout = {
        title_y = vh * 0.185,
        options_start_y = vh * 0.32,
        option_spacing = 50,
        hint_y = vh - 30
    }

    -- Create semi-transparent overlay with fade-in effect
    self.overlay_alpha = 0
    self.target_alpha = 0.7

    -- Mouse interaction
    self.mouse_over = 0
    self.previous_mouse_over = 0
end

function pause:update(dt)
    -- Fade in overlay
    if self.overlay_alpha < self.target_alpha then
        self.overlay_alpha = math.min(self.overlay_alpha + dt * 2, self.target_alpha)
    end

    -- Get virtual mouse position
    local vmx, vmy = screen:GetVirtualMousePosition()

    -- Check if mouse is over any option
    self.previous_mouse_over = self.mouse_over
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

    -- Play navigate sound when mouse moves to different option
    if self.mouse_over ~= self.previous_mouse_over and self.mouse_over > 0 then
        sound:playSFX("menu", "navigate")
    end
end

function pause:draw()
    -- Draw previous scene (gameplay) in background
    if self.previous and self.previous.draw then
        self.previous:draw()
    end

    -- Start virtual coordinate system
    screen:Attach()

    -- Draw dark overlay
    love.graphics.setColor(0, 0, 0, self.overlay_alpha)
    love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)

    -- Draw pause menu
    love.graphics.setColor(1, 1, 1, 1)

    local title = "PAUSED"
    love.graphics.setFont(self.titleFont)
    love.graphics.printf(title, 0, self.layout.title_y, self.virtual_width, "center")

    love.graphics.setFont(self.optionFont)
    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing

        -- Highlight if selected by keyboard/gamepad or hovered by mouse
        if i == self.selected or i == self.mouse_over then
            love.graphics.setColor(1, 1, 0, 1)
            love.graphics.printf("> " .. option, 0, y, self.virtual_width, "center")
        else
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf(option, 0, y, self.virtual_width, "center")
        end
    end

    -- Draw controls hint
    local hint_text
    if input:hasGamepad() then
        hint_text = "D-Pad: Navigate | " .. input:getPrompt("menu_select") .. ": Select | " .. input:getPrompt("pause") .. ": Resume\nKeyboard: Arrow Keys / WASD | Enter: Select | ESC: Resume | Mouse: Hover & Click"
    else
        hint_text = "Arrow Keys / WASD to navigate, Enter to select, ESC to resume | Mouse to hover and click"
    end

    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.printf(hint_text, 0, self.layout.hint_y - 20, self.virtual_width, "center")

    -- End virtual coordinate system
    screen:Detach()
end

function pause:resize(w, h)
    -- Update screen scaling system
    screen:Resize(w, h)

    -- Also resize the previous scene (e.g., play scene) to keep its camera/scaling correct
    if self.previous and self.previous.resize then
        self.previous:resize(w, h)
    end
end

function pause:resume()
    -- CRITICAL: Restore scene_control.previous to game scene
    scene_control.previous = self.previous
end

function pause:keypressed(key)
    if input:wasPressed("menu_up", "keyboard", key) then
        self.previous_selected = self.selected
        self.selected = self.selected - 1
        if self.selected < 1 then
            self.selected = #self.options
        end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_down", "keyboard", key) then
        self.previous_selected = self.selected
        self.selected = self.selected + 1
        if self.selected > #self.options then
            self.selected = 1
        end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_select", "keyboard", key) then
        -- Play select sound
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    elseif input:wasPressed("pause", "keyboard", key) then
        -- Quick resume
        sound:playSFX("ui", "unpause")
        sound:resumeBGM()
        scene_control.pop()
    end
end

function pause:gamepadpressed(joystick, button)
    if input:wasPressed("menu_up", "gamepad", button) then
        self.previous_selected = self.selected
        self.selected = self.selected - 1
        if self.selected < 1 then
            self.selected = #self.options
        end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.previous_selected = self.selected
        self.selected = self.selected + 1
        if self.selected > #self.options then
            self.selected = 1
        end

        -- Play navigate sound
        if self.selected ~= self.previous_selected then
            sound:playSFX("menu", "navigate")
        end
    elseif input:wasPressed("menu_select", "gamepad", button) then
        -- Play select sound
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    elseif input:wasPressed("pause", "gamepad", button) then
        -- Quick resume
        sound:playSFX("ui", "unpause")
        sound:resumeBGM()
        scene_control.pop()
    end
end

function pause:executeOption(option_index)
    if option_index == 1 then
        -- Resume
        sound:playSFX("ui", "unpause")
        sound:resumeBGM()
        scene_control.pop()
    elseif option_index == 2 then
        -- Restart (use current save slot)
        local current_slot = self.previous.current_save_slot or 1
        local play = require "scenes.play"
        scene_control.switch(play, "assets/maps/level1/area1.lua", 400, 250, current_slot)
    elseif option_index == 3 then
        -- Settings
        local settings = require "scenes.settings"
        scene_control.push(settings)
    elseif option_index == 4 then
        -- Quit to menu
        sound:playSFX("menu", "back")
        local menu = require "scenes.menu"
        scene_control.switch(menu)
    end
end

function pause:mousepressed(x, y, button) end

function pause:mousereleased(x, y, button)
    if button == 1 then
        -- Left mouse button
        if self.mouse_over > 0 then
            self.selected = self.mouse_over

            -- Play select sound
            sound:playSFX("menu", "select")
            self:executeOption(self.selected)
        end
    end
end

return pause

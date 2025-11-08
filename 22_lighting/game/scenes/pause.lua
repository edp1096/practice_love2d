-- scenes/pause.lua

local pause = {}

local scene_control = require "engine.scene_control"
local display = require "engine.display"
local sound = require "engine.sound"
local input = require "engine.input"
local ui_scene = require "engine.ui.menu"
local restart_util = require "engine.utils.restart"
local debug = require "engine.debug"

function pause:enter(previous, ...)
    self.previous = previous
    self.options = { "Resume", "Restart from Here", "Load Last Save", "Settings", "Quit to Menu" }
    self.selected = 1
    self.mouse_over = 0

    -- Setup UI
    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh
    self.fonts = ui_scene.createMenuFonts()
    self.layout = {
        title_y = vh * 0.18,
        options_start_y = vh * 0.32,
        option_spacing = 48,
        hint_y = vh - 28
    }

    -- Fade-in effect
    self.overlay_alpha = 0
    self.target_alpha = 0.7
end

function pause:update(dt)
    -- Fade in overlay
    if self.overlay_alpha < self.target_alpha then
        self.overlay_alpha = math.min(self.overlay_alpha + dt * 2, self.target_alpha)
    end

    -- Update mouse-over
    self.mouse_over = ui_scene.updateMouseOver(self.options, self.layout, self.virtual_width, self.fonts.option)

    -- Check gamepad axis input for menu navigation (left stick)
    if input:hasGamepad() then
        if input:wasPressed("menu_up") then
            local new_sel = self.selected - 1
            if new_sel < 1 then new_sel = #self.options end
            sound:playSFX("menu", "navigate")
            self.selected = new_sel
        elseif input:wasPressed("menu_down") then
            local new_sel = self.selected + 1
            if new_sel > #self.options then new_sel = 1 end
            sound:playSFX("menu", "navigate")
            self.selected = new_sel
        end
    end
end

function pause:draw()
    -- Draw background scene (gameplay)
    if self.previous and self.previous.draw then self.previous:draw() end

    display:Attach()

    -- Draw overlay
    ui_scene.drawOverlay(self.virtual_width, self.virtual_height, self.overlay_alpha)

    -- Draw menu
    ui_scene.drawTitle("PAUSED", self.fonts.title, self.layout.title_y, self.virtual_width)
    ui_scene.drawOptions(self.options, self.selected, self.mouse_over, self.fonts.option, self.layout, self.virtual_width)

    -- Custom control hints for pause menu
    local hint_text = input:hasGamepad() and
        "D-Pad: Navigate | " .. input:getPrompt("menu_select") .. ": Select | " ..
        input:getPrompt("pause") .. ": Resume\n" ..
        "Keyboard: Arrow Keys / WASD | Enter: Select | ESC: Resume | Mouse: Hover & Click" or
        "Arrow Keys / WASD to navigate, Enter to select, ESC to resume | Mouse to hover and click"

    ui_scene.drawControlHints(self.fonts.hint, self.layout, self.virtual_width, hint_text)

    display:Detach()
end

function pause:resize(w, h)
    display:Resize(w, h)

    if self.previous and self.previous.resize then self.previous:resize(w, h) end
end

function pause:resume()
    -- Restore scene_control.previous to game scene
    scene_control.previous = self.previous
end

function pause:keypressed(key)
    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key (F1-F6), don't process pause keys
    if key:match("^f%d+$") and debug.enabled then
        return
    end

    -- Quick resume with ESC
    if input:wasPressed("pause", "keyboard", key) then
        sound:playSFX("ui", "unpause")
        sound:resumeBGM()
        scene_control.pop()

        return
    end

    -- Handle navigation
    local nav_result = ui_scene.handleKeyboardNav(key, self.selected, #self.options)

    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    end
end

function pause:gamepadpressed(joystick, button)
    -- Quick resume
    if input:wasPressed("pause", "gamepad", button) then
        sound:playSFX("ui", "unpause")
        sound:resumeBGM()
        scene_control.pop()

        return
    end

    -- Handle navigation
    local nav_result = ui_scene.handleGamepadNav(button, self.selected, #self.options)

    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    end
end

function pause:executeOption(option_index)
    if option_index == 1 then -- Resume
        sound:playSFX("ui", "unpause")
        sound:resumeBGM()
        scene_control.pop()
    elseif option_index == 2 then -- Restart from Here
        local play = require "game.scenes.play"
        local map, x, y, slot = restart_util:fromCurrentMap(self.previous)
        scene_control.switch(play, map, x, y, slot)
    elseif option_index == 3 then -- Load Last Save
        local play = require "game.scenes.play"
        local map, x, y, slot = restart_util:fromLastSave(self.previous)
        scene_control.switch(play, map, x, y, slot)
    elseif option_index == 4 then -- Settings
        local settings = require "game.scenes.settings"
        scene_control.push(settings)
    elseif option_index == 5 then -- Quit to Menu
        sound:playSFX("menu", "back")
        local menu = require "game.scenes.menu"
        scene_control.switch("menu")
    end
end

function pause:mousepressed(x, y, button) end

function pause:mousereleased(x, y, button)
    if button == 1 and self.mouse_over > 0 then
        self.selected = self.mouse_over
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    end
end

function pause:touchpressed(id, x, y, dx, dy, pressure)
    self.mouse_over = ui_scene.handleTouchPress(
        self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
    return false
end

function pause:touchreleased(id, x, y, dx, dy, pressure)
    local touched = ui_scene.handleTouchPress(
        self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
    if touched > 0 then
        self.selected = touched
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
        return true
    end
    return false
end

return pause

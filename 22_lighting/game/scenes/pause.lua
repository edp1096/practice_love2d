-- scenes/pause.lua

local MenuSceneBase = require "engine.ui.menu.base"
local scene_control = require "engine.scene_control"
local sound = require "engine.sound"
local input = require "engine.input"
local restart_util = require "engine.utils.restart"
local display = require "engine.display"

-- Option selection handler
local function onSelect(self, option_index)
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

-- Custom keypressed handler for quick resume
local function customKeypressed(self, key)
    local debug = require "engine.debug"

    -- Handle debug keys first
    debug:handleInput(key, {})

    -- If debug mode consumed the key, don't process pause keys
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

    -- Handle navigation (call base implementation)
    local ui_helpers = require "engine.ui.menu.helpers"
    local nav_result = ui_helpers.handleKeyboardNav(key, self.selected, #self.options)

    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    end
end

-- Custom gamepadpressed handler for quick resume
local function customGamepadpressed(self, joystick, button)
    -- Quick resume
    if input:wasPressed("pause", "gamepad", button) then
        sound:playSFX("ui", "unpause")
        sound:resumeBGM()
        scene_control.pop()
        return
    end

    -- Handle navigation (call base implementation)
    local ui_helpers = require "engine.ui.menu.helpers"
    local nav_result = ui_helpers.handleGamepadNav(button, self.selected, #self.options)

    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    end
end

-- Custom layout for pause menu
local vw, vh = display:GetVirtualDimensions()
local pause_layout = {
    title_y = vh * 0.18,
    options_start_y = vh * 0.32,
    option_spacing = 48,
    hint_y = vh - 28
}

-- Custom control hints for pause menu
local pause_hints = input:hasGamepad() and
    "D-Pad: Navigate | " .. input:getPrompt("menu_select") .. ": Select | " ..
    input:getPrompt("pause") .. ": Resume\n" ..
    "Keyboard: Arrow Keys / WASD | Enter: Select | ESC: Resume | Mouse: Hover & Click" or
    "Arrow Keys / WASD to navigate, Enter to select, ESC to resume | Mouse to hover and click"

-- Create pause scene using base
local pause = MenuSceneBase:create({
    title = "PAUSED",
    options = { "Resume", "Restart from Here", "Load Last Save", "Settings", "Quit to Menu" },
    on_select = onSelect,
    layout = pause_layout,
    control_hints = pause_hints,
    background_scene = true,
    overlay_alpha = 0.7
})

-- Override keypressed to handle quick resume
pause.keypressed = customKeypressed

-- Override gamepadpressed to handle quick resume
pause.gamepadpressed = customGamepadpressed

return pause

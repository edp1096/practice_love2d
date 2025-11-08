-- scenes/menu.lua

local MenuSceneBase = require "engine.ui.menu.base"
local scene_control = require "engine.scene_control"
local save_sys = require "engine.save"
local sound = require "engine.sound"
local constants = require "engine.constants"
local text_ui = require "engine.ui.text"

-- Custom enter logic for main menu
local function onEnter(self, previous, ...)
    local has_saves = save_sys:hasSaveFiles()
    self.options = has_saves and
        { "Continue", "New Game", "Load Game", "Settings", "Quit" } or
        { "New Game", "Settings", "Quit" }
    self.selected = 1

    -- Play menu BGM (only restart from beginning if not coming from load scene)
    local load_scene = require "game.scenes.load"
    if previous ~= load_scene then
        sound:playBGM("menu", 1.0, true)
    end
end

-- Custom draw logic for main menu
local function onDraw(self)
    local input = require "engine.input"
    local debug = require "engine.debug"

    if input:hasGamepad() then
        text_ui:draw("Controller: " .. input.joystick_name, 10, 10, {0.3, 0.8, 0.3, 1})
    end

    if debug.enabled then
        debug:drawHelp(self.virtual_width - 250, 10)
    end
end

-- Option selection handler
local function onSelect(self, option_index)
    local option_name = self.options[option_index]

    if option_name == "Continue" then
        local recent_slot = save_sys:getMostRecentSlot()
        if recent_slot then
            local save_data = save_sys:loadGame(recent_slot)
            if save_data then
                local play = require "game.scenes.play"
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

        -- Start with level1 intro
        scene_control.switch("intro",
            "level1",
            constants.GAME_START.DEFAULT_MAP,
            constants.GAME_START.DEFAULT_SPAWN_X,
            constants.GAME_START.DEFAULT_SPAWN_Y,
            slot)
    elseif option_name == "Load Game" then
        local load = require "game.scenes.load"
        scene_control.switch(load)
    elseif option_name == "Settings" then
        local settings = require "game.scenes.settings"
        scene_control.switch(settings)
    elseif option_name == "Quit" then
        love.event.quit()
    end
end

-- Back handler (ESC key)
local function onBack(self)
    love.event.quit()
end

-- Create menu scene using base
local menu = MenuSceneBase:create({
    title = "Hello Love2D",
    options = { "New Game", "Settings", "Quit" }, -- Default options, overridden in onEnter
    on_enter = onEnter,
    on_select = onSelect,
    on_back = onBack,
    on_draw = onDraw,
    show_debug = true
})

return menu

-- scenes/gameover.lua
-- Game Over/Clear scene displayed when player dies or wins

local MenuSceneBase = require "engine.ui.menu.base"
local scene_control = require "engine.scene_control"
local sound = require "engine.sound"
local input = require "engine.input"
local restart_util = require "engine.utils.restart"
local fonts = require "engine.utils.fonts"
local text_ui = require "engine.ui.text"
local display = require "engine.display"

-- State for clear vs game over
local is_clear_state = false

-- Custom enter logic
local function onEnter(self, previous, is_clear, ...)
    is_clear_state = is_clear or false
    self.is_clear = is_clear_state

    if is_clear_state then
        self.title = "GAME CLEAR!"
        self.subtitle = "Victory!"
        self.options = { "Main Menu" }
        sound:playBGM("victory", 1.0, true)
    else
        self.title = "GAME OVER"
        self.subtitle = "You Have Fallen"
        self.options = { "Restart from Here", "Load Last Save", "Main Menu" }
        sound:playBGM("gameover", 1.0, true)
    end

    -- Custom fonts
    self.titleFont = fonts.title_large
    self.subtitleFont = fonts.subtitle

    -- Custom layout
    local vh = self.virtual_height
    self.layout = {
        title_y = vh * 0.24,
        subtitle_y = vh * 0.34,
        options_start_y = vh * 0.49,
        option_spacing = 48,
        hint_y = vh - 28
    }

    -- Flash effect
    if is_clear_state then
        self.flash_alpha = 1.0
        self.flash_speed = 1.5
        self.flash_color = { 1, 0.8, 0 }
    else
        self.flash_alpha = 1.0
        self.flash_speed = 2.0
        self.flash_color = { 0.8, 0, 0 }
    end
end

-- Custom update logic
local function onUpdate(self, dt)
    if self.flash_alpha > 0 then
        self.flash_alpha = math.max(0, self.flash_alpha - self.flash_speed * dt)
    end
end

-- Custom draw logic
local function onDraw(self)
    -- Draw flash effect
    if self.flash_alpha > 0 then
        love.graphics.setColor(self.flash_color[1], self.flash_color[2], self.flash_color[3], self.flash_alpha * 0.3)
        love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)
    end

    -- Draw title and subtitle
    if self.is_clear then
        text_ui:drawCentered(self.title, self.layout.title_y, self.virtual_width, {1, 0.9, 0.2, 1}, self.titleFont)
        text_ui:drawCentered(self.subtitle, self.layout.subtitle_y, self.virtual_width, {0.9, 0.9, 0.9, 1}, self.subtitleFont)
    else
        text_ui:drawCentered(self.title, self.layout.title_y, self.virtual_width, {1, 0.2, 0.2, 1}, self.titleFont)
        text_ui:drawCentered(self.subtitle, self.layout.subtitle_y, self.virtual_width, {0.8, 0.8, 0.8, 1}, self.subtitleFont)
    end
end

-- Option selection handler
local function onSelect(self, option_index)
    if self.is_clear then
        if option_index == 1 then -- Main Menu
            scene_control.switch("menu")
        end
    else
        if option_index == 1 then -- Restart from Here
            local play = require "game.scenes.play"
            local map, x, y, slot = restart_util:fromCurrentMap(self.previous)
            scene_control.switch(play, map, x, y, slot)
        elseif option_index == 2 then -- Load Last Save
            local play = require "game.scenes.play"
            local map, x, y, slot = restart_util:fromLastSave(self.previous)
            scene_control.switch(play, map, x, y, slot)
        elseif option_index == 3 then -- Main Menu
            scene_control.switch("menu")
        end
    end
end

-- Back handler (ESC key)
local function onBack(self)
    scene_control.switch("menu")
end

-- Custom control hints
local function getHints()
    if input:hasGamepad() then
        return "D-Pad: Navigate | " ..
            input:getPrompt("menu_select") .. ": Select | " ..
            input:getPrompt("menu_back") .. ": Main Menu\n" ..
            "Keyboard: Arrow Keys / WASD | Enter: Select | ESC: Main Menu | Mouse: Hover & Click"
    else
        return "Arrow Keys / WASD to navigate, Enter to select | Mouse to hover and click"
    end
end

-- Create gameover scene using base
local gameover = MenuSceneBase:create({
    title = "GAME OVER",
    options = { "Restart from Here", "Load Last Save", "Main Menu" },
    on_enter = onEnter,
    on_update = onUpdate,
    on_draw = onDraw,
    on_select = onSelect,
    on_back = onBack,
    control_hints = getHints(),
    background_scene = true,
    overlay_alpha = 0.8
})

return gameover

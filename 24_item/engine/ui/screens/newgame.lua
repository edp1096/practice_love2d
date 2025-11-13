-- engine/ui/screens/newgame.lua
-- New game slot selection scene

local SlotSceneBase = require "engine.ui.screens.base.slot_scene"
local newgame = SlotSceneBase:new()

local scene_control = require "engine.core.scene_control"
local constants = require "engine.core.constants"
local text_ui = require "engine.utils.text"

-- Customize title
function newgame:getTitle()
    return "Select Save Slot"
end

-- Customize action label
function newgame:getActionLabel()
    return "Start"
end

-- Override slot rendering for newgame-specific display
function newgame:drawSlot(slot, i, y, is_selected)
    local shapes = require "engine.utils.shapes"
    local is_hovered = (i == self.mouse_over)
    local state = is_selected and "selected" or (is_hovered and "hover" or "normal")
    shapes:drawButton(self.virtual_width * 0.15, y - 5, self.virtual_width * 0.7, 75, state, 0)

    if slot.slot == "back" then
        love.graphics.setFont(self.slotFont)
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(0.8, 0.8, 0.8, 1)
        end
        love.graphics.printf(slot.display_name, 0, y + 24, self.virtual_width, "center")
    elseif slot.exists then
        -- Existing slot - show "Overwrite?" warning
        local title_color = is_selected and {1, 0.7, 0, 1} or {1, 1, 1, 1}
        text_ui:draw("Slot " .. slot.slot .. " (Overwrite?)", self.virtual_width * 0.2, y, title_color, self.slotFont)
        self:drawSlotInfo(slot, y)
    else
        -- Empty slot - show "New Game"
        local new_color = is_selected and {0, 1, 0.5, 1} or {0.7, 0.7, 0.7, 1}
        text_ui:draw("Slot " .. slot.slot .. " - New Game", self.virtual_width * 0.2, y + 24, new_color, self.slotFont)
    end
end

-- Implement slot selection
function newgame:selectSlot(slot_index)
    local slot = self.slots[slot_index]

    if slot.slot == "back" then
        scene_control.switch("menu")
    else
        -- Start new game with intro cutscene
        -- Pass is_new_game flag to prevent loading old save data
        scene_control.switch("cutscene",
            constants.GAME_START.DEFAULT_INTRO_ID,
            constants.GAME_START.DEFAULT_MAP,
            constants.GAME_START.DEFAULT_SPAWN_X,
            constants.GAME_START.DEFAULT_SPAWN_Y,
            slot.slot,
            true)  -- is_new_game = true
    end
end

return newgame

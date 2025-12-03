-- engine/ui/screens/settings/render.lua
-- Rendering for settings menu

local render = {}

local display = require "engine.core.display"
local input = require "engine.core.input"
local text_ui = require "engine.utils.text"
local options_module = require "engine.ui.screens.settings.options"
local colors = require "engine.utils.colors"
local locale = require "engine.core.locale"

function render:draw(state)
    -- Draw previous scene in background if it exists
    if state.previous and state.previous.draw then
        state.previous:draw()
    else
        colors:apply(colors.NAVY_BLUE)
        love.graphics.clear(love.graphics.getColor())
    end

    display:Attach()

    -- Draw semi-transparent overlay
    if state.previous then
        colors:apply(colors.for_dialog_dark)
        love.graphics.rectangle("fill", 0, 0, state.virtual_width, state.virtual_height)
    end

    colors:reset()

    -- Title (use locale)
    text_ui:drawCentered(locale:t("settings.title"), state.layout.title_y, state.virtual_width, colors.for_text_normal, state.titleFont)

    -- Draw settings options
    for i, option in ipairs(state.options) do
        local y = state.layout.options_start_y + (i - 1) * state.layout.option_spacing
        local is_selected = (i == state.selected)

        -- Draw label
        text_ui:drawOptionAligned(option.name, 0, y, state.layout.label_x, "right", is_selected, state.labelFont)

        -- Draw value
        local value_text = options_module:getOptionValue(state, i)
        if option.type ~= "action" then
            local value_color = is_selected and colors.for_menu_selected or colors.for_text_normal
            text_ui:drawf(value_text, state.layout.value_x, y, state.virtual_width - state.layout.value_x - 100, "left", value_color, state.valueFont)
        end

        -- Draw arrows for adjustable options
        if is_selected and option.type ~= "action" then
            love.graphics.setFont(state.valueFont)
            local value_width = state.valueFont:getWidth(value_text)
            text_ui:draw("< >", state.layout.value_x + value_width + 20, y, colors.for_settings_arrow)
        end
    end

    -- Controls hint
    local hint_text
    if input:hasGamepad() then
        hint_text = input:getPrompt("menu_back") .. ": Back | " ..
            input:getPrompt("menu_select") .. ": Select | D-Pad/Left-Right: Change"
    else
        hint_text = "ESC: Back | Enter: Select | Arrow/WASD: Navigate | Left-Right: Change"
    end
    text_ui:drawCentered(hint_text, state.layout.hint_y - 20, state.virtual_width, colors.for_text_dim, state.hintFont)

    display:Detach()

    -- Debug info now drawn in app_lifecycle (main.lua)
    display:ShowVirtualMouse()
end

return render

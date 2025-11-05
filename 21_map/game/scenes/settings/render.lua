-- scenes/settings/render.lua
-- Rendering for settings menu

local render = {}

local screen = require "lib.screen"
local input = require "engine.input"
local options_module = require "game.scenes.settings.options"

function render:draw(state)
    -- Draw previous scene in background if it exists
    if state.previous and state.previous.draw then
        state.previous:draw()
    else
        love.graphics.clear(0.1, 0.1, 0.15, 1)
    end

    -- Draw semi-transparent overlay
    if state.previous then
        screen:Attach()
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", 0, 0, state.virtual_width, state.virtual_height)
        screen:Detach()
    end

    love.graphics.setColor(1, 1, 1, 1)

    screen:Attach()

    love.graphics.setFont(state.titleFont)
    love.graphics.printf("Settings", 0, state.layout.title_y, state.virtual_width, "center")

    -- Draw settings options
    for i, option in ipairs(state.options) do
        local y = state.layout.options_start_y + (i - 1) * state.layout.option_spacing
        local is_selected = (i == state.selected or i == state.mouse_over)

        -- Draw label
        love.graphics.setFont(state.labelFont)
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
        end
        love.graphics.printf(option.name, 0, y, state.layout.label_x, "right")

        -- Draw value
        love.graphics.setFont(state.valueFont)
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end

        local value_text = options_module:getOptionValue(state, i)
        if option.type ~= "action" then
            love.graphics.printf(value_text, state.layout.value_x, y, state.virtual_width - state.layout.value_x - 100, "left")
        end

        -- Draw arrows for adjustable options
        if is_selected and option.type ~= "action" then
            love.graphics.setColor(0.5, 0.5, 1, 1)
            local value_width = state.valueFont:getWidth(value_text)
            love.graphics.printf("< >", state.layout.value_x + value_width + 20, y, state.virtual_width - state.layout.value_x - value_width - 20, "left")
        end
    end

    -- Controls hint
    love.graphics.setFont(state.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)

    local hint_text
    if input:hasGamepad() then
        hint_text = input:getPrompt("menu_back") .. ": Back | " ..
            input:getPrompt("menu_select") .. ": Select | D-Pad/Left-Right: Change"
    else
        hint_text = "ESC: Back | Enter: Select | Arrow/WASD: Navigate | Left-Right: Change"
    end

    love.graphics.printf(hint_text, 0, state.layout.hint_y - 20, state.virtual_width, "center")

    screen:Detach()

    -- Debug info now drawn in app_lifecycle (main.lua)
    screen:ShowVirtualMouse()
end

return render

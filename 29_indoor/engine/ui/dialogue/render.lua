-- engine/ui/dialogue/render.lua
-- Dialogue rendering functions

local Talkies = require "vendor.talkies"
local colors = require "engine.utils.colors"

local render = {}

-- Update button visibility based on dialogue state
function render:updateButtonVisibility(dialogue)
    local is_open = dialogue:isOpen()
    local talkies_open = Talkies.isOpen()
    local has_choices = dialogue.current_choices and #dialogue.current_choices > 0
    local is_paged_text = dialogue.showing_paged_text and dialogue.current_pages

    -- Buttons should show when:
    -- 1. Dialogue is open (isOpen() = true)
    -- 2. EITHER Talkies is showing OR we're in paged text mode
    -- 3. No choices are shown (has_choices = false)
    local should_show = is_open and (talkies_open or is_paged_text) and not has_choices

    if should_show then
        if dialogue.skip_button then dialogue.skip_button:show() end
        if dialogue.next_button then dialogue.next_button:show() end
    else
        if dialogue.skip_button then dialogue.skip_button:hide() end
        if dialogue.next_button then dialogue.next_button:hide() end
    end
end

-- Main draw function
function render:draw(dialogue)
    -- Don't draw anything if dialogue is closed
    if not dialogue:isOpen() then
        return
    end

    local has_choices = dialogue.tree_mode and dialogue.current_choices and #dialogue.current_choices > 0
    local showing_paged = dialogue.showing_paged_text and dialogue.current_pages

    -- PAGED MODE: Draw current page or choices
    if showing_paged then
        -- On last page and choices available - show choices
        if dialogue.current_page_index >= dialogue.total_pages - 1 and has_choices then
            self:drawDialogueBoxForChoices(dialogue)
            self:drawChoices(dialogue)
        else
            -- Show current page text
            self:drawPagedText(dialogue)
        end
    -- TALKIES MODE: Draw Talkies or choices
    elseif not has_choices then
        Talkies.draw()
    else
        -- Draw choice buttons (if in tree mode and choices available)
        self:drawDialogueBoxForChoices(dialogue)
        self:drawChoices(dialogue)
    end

    -- Draw buttons on top of dialogue (visibility managed by update())
    if dialogue.next_button then
        dialogue.next_button:draw()
    end
    if dialogue.skip_button then
        dialogue.skip_button:draw()
    end
end

-- Draw paged text (custom renderer for multi-page dialogue)
function render:drawPagedText(dialogue)
    if not dialogue.display or not dialogue.current_pages then return end

    local vw, vh = dialogue.display:GetVirtualDimensions()
    local padding = 10
    local font = Talkies.font or love.graphics.getFont()
    local extra_height = font:getHeight() * 1.5
    local boxH = vh * 0.4 - (2 * padding) + extra_height
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    -- Get current node for speaker name
    local node = dialogue.current_tree.nodes[dialogue.current_node_id]
    local speaker = node and node.speaker or "???"

    -- Draw dialogue box background
    colors:apply(colors.for_dialogue_bg)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4, 4)

    -- Draw border
    colors:apply(colors.for_dialogue_text)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 4, 4)

    -- Draw speaker name (title box)
    if speaker ~= "" then
        local titleFont = dialogue.choice_font or love.graphics.getFont()
        love.graphics.setFont(titleFont)
        local titleBoxW = titleFont:getWidth(speaker) + (2 * padding)
        local titleBoxH = titleFont:getHeight() + padding
        local titleBoxY = boxY - titleBoxH - (padding / 2)
        local titleX, titleY = boxX + padding, titleBoxY + 2

        -- Title background
        colors:apply(colors.for_dialogue_bg)
        love.graphics.rectangle("fill", boxX, titleBoxY, titleBoxW, titleBoxH, 4, 4)

        -- Title border
        colors:apply(colors.for_dialogue_text)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", boxX, titleBoxY, titleBoxW, titleBoxH, 4, 4)

        -- Title text
        colors:apply(colors.for_dialogue_speaker)
        love.graphics.print(speaker, titleX, titleY)
    end

    -- Draw current page text
    local textFont = Talkies.font or love.graphics.getFont()
    love.graphics.setFont(textFont)
    local textX = boxX + padding + 5
    local textY = boxY + padding
    local textWidth = boxW - (2 * padding) - 10

    local currentText = dialogue.current_pages[dialogue.current_page_index + 1] or ""
    colors:apply(colors.for_dialogue_text)
    love.graphics.printf(currentText, textX, textY, textWidth, "left")

    -- Draw page indicator (1/3)
    local pageIndicator = string.format("%d/%d", dialogue.current_page_index + 1, dialogue.total_pages)
    local indicatorX = boxX + boxW - padding - textFont:getWidth(pageIndicator)
    local indicatorY = boxY + boxH - padding - textFont:getHeight()
    colors:apply(colors.for_dialogue_page_indicator)
    love.graphics.print(pageIndicator, indicatorX, indicatorY)

    -- Reset
    colors:reset()
    love.graphics.setLineWidth(1)
end

-- Draw dialogue box background for choices (mimics Talkies style)
function render:drawDialogueBoxForChoices(dialogue)
    if not dialogue.display then return end

    local vw, vh = dialogue.display:GetVirtualDimensions()
    local padding = 10

    -- Use standard dialogue box height + extra text space
    local font = Talkies.font or love.graphics.getFont()
    local extra_height = font:getHeight() * 1.5
    local boxH = vh * 0.4 - (2 * padding) + extra_height
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    -- Get current node for speaker and text
    -- Priority: Use dialogue.current_node (for dynamic virtual nodes)
    -- Fallback: Lookup in tree by ID
    local node = dialogue.current_node or
                 (dialogue.current_tree and dialogue.current_tree.nodes[dialogue.current_node_id])
    local speaker = node and node.speaker or "???"
    local text = node and node.text or ""

    -- Draw dialogue box background
    colors:apply(colors.for_dialogue_bg)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4, 4)

    -- Draw border
    colors:apply(colors.for_dialogue_text)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 4, 4)

    -- Draw speaker name (title box above dialogue)
    if speaker ~= "" then
        local titleFont = dialogue.choice_font or love.graphics.getFont()
        love.graphics.setFont(titleFont)
        local titleBoxW = titleFont:getWidth(speaker) + (2 * padding)
        local titleBoxH = titleFont:getHeight() + padding
        local titleBoxY = boxY - titleBoxH - (padding / 2)
        local titleX, titleY = boxX + padding, titleBoxY + 2

        -- Title background
        colors:apply(colors.for_dialogue_bg)
        love.graphics.rectangle("fill", boxX, titleBoxY, titleBoxW, titleBoxH, 4, 4)

        -- Title border
        colors:apply(colors.for_dialogue_text)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", boxX, titleBoxY, titleBoxW, titleBoxH, 4, 4)

        -- Title text
        colors:apply(colors.for_dialogue_speaker)
        love.graphics.print(speaker, titleX, titleY)
    end

    -- Draw dialogue text above choices
    if text ~= "" then
        local textFont = Talkies.font or love.graphics.getFont()
        love.graphics.setFont(textFont)
        local textX = boxX + padding + 5
        local textY = boxY + padding
        local textWidth = boxW - (2 * padding) - 10

        colors:apply(colors.for_dialogue_text)
        love.graphics.printf(text, textX, textY, textWidth, "left")
    end

    -- Reset
    colors:reset()
    love.graphics.setLineWidth(1)
end

-- Draw choice buttons
function render:drawChoices(dialogue)
    if not dialogue.display then return end

    local vw, vh = dialogue.display:GetVirtualDimensions()
    local choice_count = #dialogue.current_choices
    local choice_height = 35
    local choice_spacing = 8

    -- Calculate dialogue box dimensions (same as drawDialogueBoxForChoices)
    local padding = 10
    local font = Talkies.font or love.graphics.getFont()
    local extra_height = font:getHeight() * 1.5
    local boxH = vh * 0.4 - (2 * padding) + extra_height
    local boxY = vh - (boxH + padding)

    -- Choice width: 1/2 of screen width
    local choice_width = (vw * 1 / 2) - (2 * padding)
    local total_height = (choice_height * choice_count) + (choice_spacing * (choice_count - 1))

    -- Position choices: bottom-right corner
    local start_x = vw - choice_width - (2 * padding)
    local start_y = vh - total_height - (2 * padding)

    love.graphics.setFont(dialogue.choice_font)

    for i, choice in ipairs(dialogue.current_choices) do
        local y = start_y + ((i - 1) * (choice_height + choice_spacing))
        local is_selected = (i == dialogue.selected_choice_index)

        -- Check if this choice was previously selected
        -- Exception: "Other quest?" is never marked as selected
        local choice_key = dialogue.current_node_id .. "|" .. choice.text
        local was_selected = choice.text ~= "Other quest?" and dialogue.selected_choices[choice_key]

        -- Button background (only depends on selection, NOT visited state)
        if is_selected then
            colors:apply(colors.for_dialogue_choice_selected_bg)  -- Bright blue highlight when selected
        else
            colors:apply(colors.for_dialogue_choice_normal_bg)  -- Dark grey when not selected
        end
        love.graphics.rectangle("fill", start_x, y, choice_width, choice_height, 5, 5)

        -- Button border (only depends on selection, NOT visited state)
        if is_selected then
            colors:apply(colors.for_dialogue_choice_selected_border)  -- Bright border when selected
            love.graphics.setLineWidth(3)
        else
            colors:apply(colors.for_dialogue_choice_normal_border)  -- Normal border when not selected
            love.graphics.setLineWidth(2)
        end
        love.graphics.rectangle("line", start_x, y, choice_width, choice_height, 5, 5)

        -- Determine if choice should be greyed out (disabled appearance)
        -- Priority: 1. Explicit disabled flag (set by helpers) > 2. Previous selection
        local should_grey_out = false

        -- 1. Check if choice is explicitly disabled (set during filtering)
        if choice._is_disabled then
            should_grey_out = true
        end

        -- 2. Check previous selection (only for non-repeating choices)
        -- Common/repeating choices are always shown in white (never greyed)
        if not should_grey_out then
            local always_available_choices = {
                ["Accept Quest"] = true,  -- Quest system buttons
                ["Decline"] = true,
                ["Continue"] = true,
                ["I'll think about it"] = true,
                ["Not interested"] = true,
                ["Yes"] = true,
                ["No"] = true,
                ["Goodbye"] = true,
                ["Thanks"] = true,
                ["Good to know"] = true,
                ["Thanks for the info"] = true,
                ["Tell me more"] = true,
                ["I'll get right on it"] = true
            }
            local is_always_available = always_available_choices[choice.text]

            if was_selected and not is_always_available then
                should_grey_out = true
            end
        end

        -- Apply color
        if should_grey_out then
            colors:apply(colors.for_dialogue_choice_text_visited)  -- Dark grey for disabled/selected
        else
            colors:apply(colors.for_dialogue_choice_text_normal)  -- White for available
        end
        local text_y = y + (choice_height - dialogue.choice_font:getHeight()) / 2
        love.graphics.printf(choice.text, start_x + 10, text_y, choice_width - 20, "left")
    end

    colors:reset()
    love.graphics.setLineWidth(1)
end

return render

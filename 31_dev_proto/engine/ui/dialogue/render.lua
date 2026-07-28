-- engine/ui/dialogue/render.lua
-- Dialogue rendering functions

local utf8 = require "utf8"
local colors = require "engine.utils.colors"
local core = require "engine.ui.dialogue.core"

local render = {}

-- Helper: Extract substring by UTF-8 character count
local function utf8_sub(str, start_char, end_char)
    if not str or str == "" then return "" end
    local byte_start = 1
    local byte_end = #str
    local char_count = 0

    for pos, _ in utf8.codes(str) do
        char_count = char_count + 1
        if char_count == start_char then
            byte_start = pos
        end
        if char_count == end_char + 1 then
            byte_end = pos - 1
            break
        end
    end

    if end_char >= char_count then
        byte_end = #str
    end

    return str:sub(byte_start, byte_end)
end

-- Update button visibility based on dialogue state
function render:updateButtonVisibility(dialogue)
    local is_open = dialogue:isOpen()
    local has_choices = dialogue.current_choices and #dialogue.current_choices > 0
    local is_paged_text = dialogue.showing_paged_text and dialogue.current_pages
    local is_single_text = dialogue.showing_single_text

    -- Buttons should show when:
    -- 1. Dialogue is open (isOpen() = true)
    -- 2. We're in paged text mode OR single text mode
    -- 3. No choices are shown (has_choices = false)
    local should_show = is_open and (is_paged_text or is_single_text) and not has_choices

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
        -- On last page and choices available - show choices (only after typewriter completes)
        if dialogue.current_page_index >= dialogue.total_pages - 1 and has_choices and dialogue.typewriter_complete then
            self:drawDialogueBoxForChoices(dialogue)
            self:drawChoices(dialogue)
        else
            -- Show current page text
            self:drawPagedText(dialogue)
        end
    -- SINGLE TEXT MODE: Draw single text with typewriter
    elseif dialogue.showing_single_text then
        self:drawSingleText(dialogue)
    -- CHOICES MODE: Draw text + choices
    elseif has_choices then
        self:drawDialogueBoxForChoices(dialogue)
        -- Only show choices after typewriter completes
        if dialogue.typewriter_complete then
            self:drawChoices(dialogue)
        end
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
    local font = core.font or love.graphics.getFont()
    local extra_height = font:getHeight() * 1.5
    local boxH = vh * 0.4 - (2 * padding) + extra_height
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    -- Get resolved speaker name (translated in core.lua)
    local speaker = dialogue.current_speaker or "???"

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

    -- Draw current page text (with typewriter effect)
    local textFont = core.font or love.graphics.getFont()
    love.graphics.setFont(textFont)
    local textX = boxX + padding + 5
    local textY = boxY + padding
    local textWidth = boxW - (2 * padding) - 10

    local currentText = dialogue.current_pages[dialogue.current_page_index + 1] or ""

    -- Apply typewriter effect
    local displayText = currentText
    if not dialogue.typewriter_complete then
        local char_count = math.floor(dialogue.typewriter_position)
        displayText = utf8_sub(currentText, 1, char_count) .. "|"  -- Add cursor
    end

    colors:apply(colors.for_dialogue_text)
    love.graphics.printf(displayText, textX, textY, textWidth, "left")

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

-- Draw single text (no choices, no pages) with typewriter effect
function render:drawSingleText(dialogue)
    if not dialogue.display then return end

    local vw, vh = dialogue.display:GetVirtualDimensions()
    local padding = 10
    local font = core.font or love.graphics.getFont()
    local extra_height = font:getHeight() * 1.5
    local boxH = vh * 0.4 - (2 * padding) + extra_height
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    local speaker = dialogue.current_speaker or "???"
    local text = dialogue.current_text or ""

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

    -- Draw text with typewriter effect
    local textFont = core.font or love.graphics.getFont()
    love.graphics.setFont(textFont)
    local textX = boxX + padding + 5
    local textY = boxY + padding
    local textWidth = boxW - (2 * padding) - 10

    -- Apply typewriter effect
    local displayText = text
    if not dialogue.typewriter_complete then
        local char_count = math.floor(dialogue.typewriter_position)
        displayText = utf8_sub(text, 1, char_count) .. "|"  -- Add cursor
    end

    colors:apply(colors.for_dialogue_text)
    love.graphics.printf(displayText, textX, textY, textWidth, "left")

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
    local font = core.font or love.graphics.getFont()
    local extra_height = font:getHeight() * 1.5
    local boxH = vh * 0.4 - (2 * padding) + extra_height
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    -- Get resolved speaker and text (translated in core.lua)
    local speaker = dialogue.current_speaker or "???"
    local text = dialogue.current_text or ""

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

    -- Draw dialogue text above choices (with typewriter effect)
    if text ~= "" then
        local textFont = core.font or love.graphics.getFont()
        love.graphics.setFont(textFont)
        local textX = boxX + padding + 5
        local textY = boxY + padding
        local textWidth = boxW - (2 * padding) - 10

        -- Apply typewriter effect
        local displayText = text
        if not dialogue.typewriter_complete then
            local char_count = math.floor(dialogue.typewriter_position)
            displayText = utf8_sub(text, 1, char_count) .. "|"  -- Add cursor
        end

        colors:apply(colors.for_dialogue_text)
        love.graphics.printf(displayText, textX, textY, textWidth, "left")
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
    local font = core.font or love.graphics.getFont()
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
        -- Use text_key for persistence if available, fallback to text
        local choice_identifier = choice.text_key or choice.text
        local choice_key = dialogue.current_node_id .. "|" .. choice_identifier
        -- Exception: "Other quest?" is never marked as selected
        local is_other_quest = choice.text_key == "dialogue.villager_01.choice_other_quest"
        local was_selected = not is_other_quest and dialogue.selected_choices[choice_key]

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
            -- Quest action choices are always shown as unread
            local is_always_available = choice._is_quest_action

            -- Check text_key patterns for common dialogue choices
            if not is_always_available and choice.text_key then
                local always_available_key_patterns = {
                    "choice_think_about_it",
                    "choice_not_interested",
                    "choice_goodbye",
                    "choice_thanks",
                    "choice_good_to_know",
                    "choice_thanks_info",
                    "choice_tell_more",
                    "choice_get_on_it",
                    "choice_me_too",
                    "choice_see_around",
                    "choice_maybe_later",
                    "choice_keep_in_mind",
                }
                for _, pattern in ipairs(always_available_key_patterns) do
                    if choice.text_key:find(pattern) then
                        is_always_available = true
                        break
                    end
                end
            end

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

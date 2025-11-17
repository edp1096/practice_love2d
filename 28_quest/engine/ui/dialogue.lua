-- systems/dialogue.lua
-- Advanced dialogue system with choice support
-- Supports: Simple messages (Talkies), Choice trees, Quests, Rewards

local Talkies = require "vendor.talkies"
local skip_button_widget = require "engine.ui.widgets.button.skip"
local next_button_widget = require "engine.ui.widgets.button.next"
local colors = require "engine.ui.colors"

local dialogue = {}

function dialogue:initialize(display_module)
    -- Configure Talkies
    Talkies.backgroundColor = colors.for_dialogue_bg
    Talkies.textSpeed = "fast"
    Talkies.indicatorCharacter = "█"  -- Filled box cursor

    -- Set fixed font size (will be scaled by virtual coordinates)
    -- Use 18pt as base size for 960x540 virtual resolution
    Talkies.font = love.graphics.newFont(18)

    -- Create SKIP button for mobile (rightmost)
    self.skip_button = skip_button_widget:new({
        label = "SKIP",
        width = 100,
        height = 45,
        padding_x = 20,  -- Increased to move button to the left (was 15)
        padding_y = 20,
        charge_max = 0.5,
    })
    self.skip_button.visible = false  -- Hidden by default

    -- Create NEXT button for mobile (left of SKIP)
    self.next_button = next_button_widget:new({
        label = "NEXT",
        width = 100,
        height = 45,
        padding_x = 10,
        padding_y = 20,
        button_spacing = 0,  -- Space between NEXT and SKIP
    })
    self.next_button.visible = false  -- Hidden by default

    -- Choice system state
    self.tree_mode = false           -- true when showing dialogue tree
    self.current_tree = nil          -- Current dialogue tree data
    self.current_node_id = nil       -- Current node ID
    self.current_choices = nil       -- Current choice buttons (visible now)
    self.pending_choices = nil       -- Pending choices (show after text)
    self.selected_choice_index = 1  -- Currently selected choice (for keyboard/gamepad)
    self.choice_font = love.graphics.newFont(16)

    -- Force closed flag (prevents reopening until new dialogue starts)
    self.forced_closed = false

    -- Display reference
    self.display = nil

    -- Dialogue registry (injected from game) - preserve if already set
    if not self.dialogue_registry then
        self.dialogue_registry = {}
    end

    -- Paged dialogue state
    self.current_pages = nil
    self.current_page_index = 0
    self.total_pages = 0
    self.showing_paged_text = false

    -- Selected choices tracking (for grey-out effect) - PER DIALOGUE
    -- Format: { "{node_id}|{choice_text}" = true }
    self.selected_choices = {}

    -- Global storage for ALL dialogue choices (for persistence)
    -- Format: { dialogue_id = { "{node_id}|{choice_text}" = true, ... }, ... }
    -- Preserve existing data if already set (for save/load)
    if not self.all_dialogue_choices then
        self.all_dialogue_choices = {}
    end

    -- Current dialogue ID (for save/load)
    self.current_dialogue_id = nil

    -- Track which choice was pressed (to prevent click-through)
    self.pressed_choice_index = nil

    -- Quest system reference (injected from game)
    self.quest_system = nil

    -- Initialize display if provided
    if display_module then
        self:setDisplay(display_module)
    end
end

-- Set display reference for buttons
function dialogue:setDisplay(display)
    self.display = display
    if self.skip_button then
        self.skip_button:init(display)
    end
    if self.next_button then
        -- Calculate NEXT button position based on SKIP button
        self.next_button:init(display)
        self.next_button:calculatePosition(self.skip_button)
    end
end

-- ========================================
-- DIALOGUE TREE SYSTEM (NEW)
-- ========================================

-- Start a dialogue tree by ID (loads from registry)
function dialogue:showTreeById(dialogue_id)
    local dialogue_tree = self.dialogue_registry[dialogue_id]
    if not dialogue_tree then
        return
    end
    -- Store dialogue ID for persistence
    self.current_dialogue_id = dialogue_id
    self:showTree(dialogue_tree)
end

-- Start a dialogue tree (choice-based conversation)
function dialogue:showTree(dialogue_tree)
    if not dialogue_tree or not dialogue_tree.nodes then
        return
    end

    -- Reset forced_closed flag (allowing dialogue to open)
    self.forced_closed = false

    -- Load selected choices for this dialogue (instead of resetting)
    if self.current_dialogue_id then
        -- Ensure global storage exists for this dialogue
        if not self.all_dialogue_choices[self.current_dialogue_id] then
            self.all_dialogue_choices[self.current_dialogue_id] = {}
        end
        -- Share the same table reference (not a copy!)
        self.selected_choices = self.all_dialogue_choices[self.current_dialogue_id]
    else
        -- No dialogue ID - use temporary table
        self.selected_choices = {}
    end

    -- Enter tree mode
    self.tree_mode = true
    self.current_tree = dialogue_tree
    self.current_node_id = dialogue_tree.start_node or "start"
    self.selected_choice_index = 1

    -- Show first node
    self:_showNode(self.current_node_id)

    -- Update button visibility based on new state
    self:_updateButtonVisibility()
end

-- Internal: Display a specific node
function dialogue:_showNode(node_id)
    local node = self.current_tree.nodes[node_id]
    if not node then
        self:clear()
        return
    end

    -- Update current node
    self.current_node_id = node_id

    -- Check if node has pages (multi-page dialogue)
    if node.pages and #node.pages > 0 then
        -- Paged mode: store pages and start at page 0
        self.current_pages = node.pages
        self.current_page_index = 0
        self.total_pages = #node.pages
        self.showing_paged_text = true

        -- Don't show Talkies, we'll render pages ourselves
        Talkies.clearMessages()
    elseif node.choices and #node.choices > 0 then
        -- Node has choices: skip Talkies, show custom dialogue box directly
        self.current_pages = nil
        self.current_page_index = 0
        self.total_pages = 0
        self.showing_paged_text = false
        Talkies.clearMessages()
    else
        -- Single text mode: use Talkies
        self.current_pages = nil
        self.current_page_index = 0
        self.total_pages = 0
        self.showing_paged_text = false

        local speaker = node.speaker or "???"
        Talkies.say(speaker, { node.text })
    end

    -- Setup choices (if any)
    if node.choices and #node.choices > 0 then
        -- Node has choices: show immediately (Talkies already skipped above)
        self.current_choices = node.choices
        self.pending_choices = nil
        self.selected_choice_index = 1
    else
        -- No choices - this node ends dialogue or auto-advances
        self.current_choices = nil
        self.pending_choices = nil
        self.selected_choice_index = 1
    end

    -- Update button visibility (hide if choices shown)
    self:_updateButtonVisibility()
end

-- Advance dialogue tree (called when player presses action)
function dialogue:advanceTree()
    if not self.tree_mode then
        return
    end

    local node = self.current_tree.nodes[self.current_node_id]
    if not node then
        self:clear()
        return
    end

    -- PAGED MODE: Handle page navigation
    if self.showing_paged_text and self.current_pages then
        -- Advance to next page
        if self.current_page_index < self.total_pages - 1 then
            self.current_page_index = self.current_page_index + 1
            return
        else
            -- Last page reached - show choices or continue
            if self.pending_choices and #self.pending_choices > 0 then
                -- Activate pending choices
                self.current_choices = self.pending_choices
                self.pending_choices = nil
                self.selected_choice_index = 1
                return
            elseif self.current_choices and #self.current_choices > 0 then
                -- Choices already shown (stay in paged mode)
                return
            else
                -- No choices - advance to next node or end
                if node.next then
                    self:_showNode(node.next)
                else
                    self:clear()
                end
                return
            end
        end
    end

    -- TALKIES MODE: Handle Talkies text
    if Talkies.isOpen() and not Talkies.paused then
        Talkies.onAction()
        -- CRITICAL: Update button visibility after Talkies advances
        self:_updateButtonVisibility()

        -- If Talkies is still open (more messages), wait for next click
        if Talkies.isOpen() then
            return
        end
        -- Otherwise, continue to check for next node/choices (fall through)
    end

    -- Check for pending choices (text was shown, now show choices)
    if self.pending_choices then
        self.current_choices = self.pending_choices
        self.pending_choices = nil
        self:_updateButtonVisibility()  -- Hide buttons when choices shown
        return
    end

    -- If node has choices, wait for player to select
    if self.current_choices and #self.current_choices > 0 then
        return
    end

    -- No choices - check for auto-advance
    if node.next then
        self:_showNode(node.next)
    else
        self:clear()
    end
end

-- Select a choice (keyboard/gamepad navigation)
function dialogue:selectChoice(choice_index)
    if not self.tree_mode or not self.current_choices then
        return
    end

    local choice = self.current_choices[choice_index]
    if not choice then
        return
    end

    -- Mark this choice as selected (for grey-out effect)
    local choice_key = self.current_node_id .. "|" .. choice.text
    self.selected_choices[choice_key] = true

    -- Note: self.selected_choices is already a reference to
    -- self.all_dialogue_choices[self.current_dialogue_id]
    -- so no need to update global storage separately

    -- Execute choice action (if any)
    if choice.action then
        self:_executeAction(choice.action)
    end

    -- Navigate to next node
    if choice.next then
        -- Clear current state completely before navigating
        Talkies.clearMessages()
        self.showing_paged_text = false
        self.current_pages = nil
        self.current_page_index = 0
        self.total_pages = 0

        self:_showNode(choice.next)
    else
        -- No next - end dialogue
        self:clear()
    end
end

-- Navigate choice selection (keyboard/gamepad)
function dialogue:moveChoiceSelection(direction)
    if not self.tree_mode or not self.current_choices then
        return
    end

    local count = #self.current_choices
    if direction == "up" then
        self.selected_choice_index = self.selected_choice_index - 1
        if self.selected_choice_index < 1 then
            self.selected_choice_index = count
        end
    elseif direction == "down" then
        self.selected_choice_index = self.selected_choice_index + 1
        if self.selected_choice_index > count then
            self.selected_choice_index = 1
        end
    end
end

-- ========================================
-- SIMPLE DIALOGUE METHODS (non-interactive)
-- ========================================

function dialogue:showSimple(npc_name, message)
    self.forced_closed = false  -- Reset forced_closed (allowing dialogue to open)
    self.tree_mode = false  -- Disable tree mode
    self.current_choices = nil  -- No choices
    Talkies.say(npc_name, { message })

    -- Update button visibility (event-based, not polling)
    self:_updateButtonVisibility()
end

function dialogue:showMultiple(npc_name, messages)
    self.forced_closed = false  -- Reset forced_closed (allowing dialogue to open)
    self.tree_mode = false  -- Disable tree mode
    self.current_choices = nil  -- No choices
    Talkies.say(npc_name, messages)

    -- Update button visibility (event-based, not polling)
    self:_updateButtonVisibility()
end

function dialogue:isOpen()
    -- If forced closed, dialogue is definitively closed
    if self.forced_closed then
        return false
    end
    -- Otherwise, check Talkies or tree mode
    return Talkies.isOpen() or self.tree_mode
end

function dialogue:update(dt)
    Talkies.update(dt)

    -- CRITICAL: Poll dialogue state every frame to detect auto-close
    -- (Talkies can close itself when all messages are consumed)
    self:_updateButtonVisibility()

    -- Update skip button (charge system)
    if self.skip_button and self.skip_button.visible then
        self.skip_button:update(dt)
        self.skip_button:updateHover()

        -- Check if skip was triggered (fully charged)
        if self.skip_button:isFullyCharged() then
            self:clear()
            self.skip_button:reset()
        end
    end

    -- Update next button hover state (desktop)
    if self.next_button and self.next_button.visible then
        self.next_button:updateHover()
    end
end

-- Internal: Update button visibility based on current state
function dialogue:_updateButtonVisibility()
    local is_open = self:isOpen()
    local talkies_open = Talkies.isOpen()
    local has_choices = self.current_choices and #self.current_choices > 0
    local is_paged_text = self.showing_paged_text and self.current_pages

    -- Buttons should show when:
    -- 1. Dialogue is open (isOpen() = true)
    -- 2. EITHER Talkies is showing OR we're in paged text mode
    -- 3. No choices are shown (has_choices = false)
    local should_show = is_open and (talkies_open or is_paged_text) and not has_choices

    if should_show then
        if self.skip_button then self.skip_button:show() end
        if self.next_button then self.next_button:show() end
    else
        if self.skip_button then self.skip_button:hide() end
        if self.next_button then self.next_button:hide() end
    end
end

function dialogue:draw()
    -- Don't draw anything if dialogue is closed
    if not self:isOpen() then
        return
    end

    local has_choices = self.tree_mode and self.current_choices and #self.current_choices > 0
    local showing_paged = self.showing_paged_text and self.current_pages

    -- PAGED MODE: Draw current page or choices
    if showing_paged then
        -- On last page and choices available - show choices
        if self.current_page_index >= self.total_pages - 1 and has_choices then
            self:_drawDialogueBoxForChoices()
            self:_drawChoices()
        else
            -- Show current page text
            self:_drawPagedText()
        end
    -- TALKIES MODE: Draw Talkies or choices
    elseif not has_choices then
        Talkies.draw()
    else
        -- Draw choice buttons (if in tree mode and choices available)
        self:_drawDialogueBoxForChoices()
        self:_drawChoices()
    end

    -- Draw buttons on top of dialogue (visibility managed by update())
    if self.next_button then
        self.next_button:draw()
    end
    if self.skip_button then
        self.skip_button:draw()
    end
end

-- Internal: Draw paged text (custom renderer for multi-page dialogue)
function dialogue:_drawPagedText()
    if not self.display or not self.current_pages then return end

    local vw, vh = self.display:GetVirtualDimensions()
    local padding = 10
    local boxH = vh / 3 - (2 * padding)
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    -- Get current node for speaker name
    local node = self.current_tree.nodes[self.current_node_id]
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
        local titleFont = self.choice_font or love.graphics.getFont()
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

    local currentText = self.current_pages[self.current_page_index + 1] or ""
    colors:apply(colors.for_dialogue_text)
    love.graphics.printf(currentText, textX, textY, textWidth, "left")

    -- Draw page indicator (1/3)
    local pageIndicator = string.format("%d/%d", self.current_page_index + 1, self.total_pages)
    local indicatorX = boxX + boxW - padding - textFont:getWidth(pageIndicator)
    local indicatorY = boxY + boxH - padding - textFont:getHeight()
    colors:apply(colors.for_dialogue_page_indicator)
    love.graphics.print(pageIndicator, indicatorX, indicatorY)

    -- Reset
    colors:reset()
    love.graphics.setLineWidth(1)
end

-- Internal: Draw dialogue box background for choices (mimics Talkies style)
function dialogue:_drawDialogueBoxForChoices()
    if not self.display then return end

    local vw, vh = self.display:GetVirtualDimensions()
    local padding = 10

    -- Increase box height for text visibility (3 line heights for more space)
    local text_space = self.choice_font:getHeight() * 3.0
    local boxH = vh / 3 - (2 * padding) + text_space
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    -- Get current node for speaker and text
    local node = self.current_tree and self.current_tree.nodes[self.current_node_id]
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
        local titleFont = self.choice_font or love.graphics.getFont()
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

-- Internal: Draw choice buttons
function dialogue:_drawChoices()
    if not self.display then return end

    local vw, vh = self.display:GetVirtualDimensions()
    local choice_count = #self.current_choices
    local choice_height = 35
    local choice_spacing = 8

    -- Calculate dialogue box dimensions (same as _drawDialogueBoxForChoices)
    local padding = 10
    local text_space = self.choice_font:getHeight() * 3.0
    local boxH = vh / 3 - (2 * padding) + text_space  -- Increased height
    local boxY = vh - (boxH + padding)

    -- Choice width: fit inside dialogue box with padding
    local choice_width = vw - (4 * padding)
    local total_height = (choice_height * choice_count) + (choice_spacing * (choice_count - 1))

    -- Position choices: top-aligned below text with one line spacing
    local start_x = 2 * padding
    local start_y = boxY + text_space + padding

    love.graphics.setFont(self.choice_font)

    for i, choice in ipairs(self.current_choices) do
        local y = start_y + ((i - 1) * (choice_height + choice_spacing))
        local is_selected = (i == self.selected_choice_index)

        -- Check if this choice was previously selected
        local choice_key = self.current_node_id .. "|" .. choice.text
        local was_selected = self.selected_choices[choice_key]

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

        -- Button text (only depends on whether this choice was previously selected)
        if was_selected then
            colors:apply(colors.for_dialogue_choice_text_visited)  -- Dark grey text for previously selected
        else
            colors:apply(colors.for_dialogue_choice_text_normal)  -- White text for not yet selected
        end
        local text_y = y + (choice_height - self.choice_font:getHeight()) / 2
        love.graphics.printf(choice.text, start_x + 10, text_y, choice_width - 20, "left")
    end

    colors:reset()
    love.graphics.setLineWidth(1)
end

-- Internal: Get choice index at position (for mouse/touch click)
-- Returns choice index (1-based) or nil if no choice at position
function dialogue:_getChoiceAtPosition(x, y)
    if not self.display or not self.current_choices or #self.current_choices == 0 then
        return nil
    end

    -- Convert physical coordinates to virtual coordinates
    local coords = require "engine.core.coords"
    local vx, vy = coords:physicalToVirtual(x, y, self.display)

    local vw, vh = self.display:GetVirtualDimensions()
    local choice_count = #self.current_choices
    local choice_height = 35  -- Same as _drawChoices
    local choice_spacing = 8  -- Same as _drawChoices

    -- Calculate dialogue box dimensions (same as _drawDialogueBoxForChoices)
    local padding = 10
    local text_space = self.choice_font:getHeight() * 3.0
    local boxH = vh / 3 - (2 * padding) + text_space  -- Increased height
    local boxY = vh - (boxH + padding)

    -- Choice width and positioning (same as _drawChoices)
    local choice_width = vw - (4 * padding)
    local total_height = (choice_height * choice_count) + (choice_spacing * (choice_count - 1))

    -- Position choices: top-aligned below text with one line spacing (same as _drawChoices)
    local start_x = 2 * padding
    local start_y = boxY + text_space + padding

    -- Check each choice button
    for i = 1, choice_count do
        local btn_y = start_y + ((i - 1) * (choice_height + choice_spacing))

        if vx >= start_x and vx <= start_x + choice_width and
           vy >= btn_y and vy <= btn_y + choice_height then
            return i
        end
    end

    return nil
end

function dialogue:onAction()
    if self.tree_mode then
        -- Tree mode: handle choice selection or advance
        if self.current_choices and #self.current_choices > 0 then
            self:selectChoice(self.selected_choice_index)
        else
            -- No choices - advance tree
            self:advanceTree()
        end
    else
        -- Simple dialogue mode: advance Talkies and update button state
        Talkies.onAction()

        -- CRITICAL: Update button visibility after advancing
        -- If Talkies closed (no more messages), hide buttons
        self:_updateButtonVisibility()
    end
end

function dialogue:clear()
    -- Set forced_closed flag FIRST (this makes isOpen() return false immediately)
    self.forced_closed = true

    -- Clear tree state
    self.tree_mode = false
    self.current_tree = nil
    self.current_node_id = nil
    self.current_choices = nil
    self.pending_choices = nil
    self.selected_choice_index = 1

    -- Clear paged dialogue state
    self.current_pages = nil
    self.current_page_index = 0
    self.total_pages = 0
    self.showing_paged_text = false

    -- Clear Talkies message queue
    Talkies.clearMessages()

    -- Pop current dialog if exists (safe pop - max 10 times to avoid infinite loop)
    local max_pops = 10
    local count = 0
    while Talkies.isOpen() and count < max_pops do
        if Talkies.dialogs and Talkies.dialogs.pop then
            Talkies.dialogs:pop()
            count = count + 1
        else
            break
        end
    end

    -- Update button visibility (will hide since forced_closed is true)
    self:_updateButtonVisibility()
end

-- Unified input handler for all input types
-- Returns true if dialogue consumed the input, false otherwise
function dialogue:handleInput(source, ...)
    if not self:isOpen() then
        return false
    end

    if source == "keyboard" then
        -- Keyboard: check for choice navigation first
        local key = ...
        if self.tree_mode and self.current_choices and #self.current_choices > 0 then
            if key == "up" or key == "w" then
                self:moveChoiceSelection("up")
                return true
            elseif key == "down" or key == "s" then
                self:moveChoiceSelection("down")
                return true
            end
        end
        -- Otherwise, advance dialogue/select choice
        self:onAction()
        return true

    elseif source == "mouse" then
        local x, y = ...
        -- Mouse: check buttons first, then advance
        if not self:touchPressed(0, x, y) then
            -- Only advance if no choices are displayed (prevent accidental selection)
            if not (self.tree_mode and self.current_choices and #self.current_choices > 0) then
                self:onAction()
            end
        end
        return true

    elseif source == "mouse_release" then
        local x, y = ...
        -- Mouse release: handle button actions
        return self:touchReleased(0, x, y)

    elseif source == "touch" then
        local id, x, y = ...
        -- Touch: check buttons first, then advance
        if self:touchPressed(id, x, y) then
            return true  -- Button consumed
        end
        -- Only advance if no choices are displayed (prevent accidental selection)
        if not (self.tree_mode and self.current_choices and #self.current_choices > 0) then
            self:onAction()
        end
        return true

    elseif source == "touch_release" then
        local id, x, y = ...
        -- Touch release: handle button actions
        return self:touchReleased(id, x, y)

    elseif source == "touch_move" then
        local id, x, y = ...
        -- Touch move: update button hover states (doesn't consume input)
        self:touchMoved(id, x, y)
        return false
    end

    return false
end

-- Handle touch/mouse press on buttons and choices
function dialogue:touchPressed(id, x, y)
    if not self:isOpen() then
        return false
    end

    -- Priority 1: Check choice buttons (if visible)
    if self.tree_mode and self.current_choices and #self.current_choices > 0 then
        local choice_index = self:_getChoiceAtPosition(x, y)
        if choice_index then
            -- Highlight the choice being pressed AND remember which one
            self.selected_choice_index = choice_index
            self.pressed_choice_index = choice_index
            return true
        end
    end

    -- Priority 2: NEXT button (left of SKIP)
    if self.next_button and self.next_button:touchPressed(id, x, y) then
        return true  -- Consumed by next button
    end

    -- Priority 3: SKIP button
    if self.skip_button and self.skip_button:touchPressed(id, x, y) then
        return true  -- Consumed by skip button
    end

    return false
end

-- Handle touch/mouse release on buttons and choices
function dialogue:touchReleased(id, x, y)
    -- Always process button releases even if dialogue closed
    -- (to clean up button pressed state)
    local button_consumed = false

    -- Priority 1: NEXT button - advances to next message
    if self.next_button and self.next_button:touchReleased(id, x, y) then
        if self:isOpen() then
            self:onAction()  -- Advance dialogue (only if still open)
        end
        button_consumed = true
    end

    -- Priority 2: SKIP button - clears all dialogue (only if fully charged)
    if self.skip_button and self.skip_button:touchReleased(id, x, y) then
        if self:isOpen() then
            -- touchReleased returns true only if fully charged
            self:clear()  -- Clear all dialogue
        end
        button_consumed = true
    end

    if button_consumed then
        return true
    end

    -- Early exit if dialogue is closed (after button processing)
    if not self:isOpen() then
        return false
    end

    -- Priority 3: Check choice buttons (if visible)
    if self.tree_mode and self.current_choices and #self.current_choices > 0 then
        local choice_index = self:_getChoiceAtPosition(x, y)
        -- Only select if released on the SAME choice that was pressed (prevent click-through)
        if choice_index and choice_index == self.pressed_choice_index then
            -- Select the clicked choice
            self:selectChoice(choice_index)
            self.pressed_choice_index = nil  -- Reset
            return true
        end
        -- Reset even if released on a different choice
        self.pressed_choice_index = nil
    end

    return false
end

-- Handle touch/mouse move
function dialogue:touchMoved(id, x, y)
    if self:isOpen() then
        -- Check for choice hover (mouse/touch move)
        if self.tree_mode and self.current_choices and #self.current_choices > 0 then
            local hover_index = self:_getChoiceAtPosition(x, y)
            if hover_index then
                self.selected_choice_index = hover_index
            end
        end

        if self.skip_button then
            self.skip_button:touchMoved(id, x, y)
        end
        if self.next_button then
            self.next_button:touchMoved(id, x, y)
        end
    end
end

-- ========================================
-- PERSISTENCE SYSTEM
-- ========================================

-- Export dialogue choice history (for save system)
-- Returns a table ready to be saved to file
function dialogue:exportChoiceHistory()
    return self.all_dialogue_choices
end

-- Import dialogue choice history (from save file)
-- Merges with existing history
function dialogue:importChoiceHistory(history)
    if not history then
        return
    end

    -- Ensure all_dialogue_choices exists (in case called before initialize)
    if not self.all_dialogue_choices then
        self.all_dialogue_choices = {}
    end

    -- Merge loaded history with current state
    for dialogue_id, choices in pairs(history) do
        if not self.all_dialogue_choices[dialogue_id] then
            self.all_dialogue_choices[dialogue_id] = {}
        end
        for choice_key, value in pairs(choices) do
            self.all_dialogue_choices[dialogue_id][choice_key] = value
        end
    end
end

-- Clear all dialogue history (for new game)
function dialogue:clearAllHistory()
    self.all_dialogue_choices = {}
    self.selected_choices = {}
    self.current_dialogue_id = nil
end

-- Clear history for a specific dialogue (optional utility)
function dialogue:clearDialogueHistory(dialogue_id)
    if self.all_dialogue_choices[dialogue_id] then
        self.all_dialogue_choices[dialogue_id] = nil
    end

    -- If this is the current dialogue, also clear local state
    if self.current_dialogue_id == dialogue_id then
        self.selected_choices = {}
    end
end

-- ========================================
-- ACTION SYSTEM (for quests, events, etc.)
-- ========================================

-- Execute action from dialogue choice
function dialogue:_executeAction(action)
    if not action or not action.type then
        return
    end

    -- Quest actions
    if action.type == "accept_quest" then
        if self.quest_system and action.quest_id then
            local success = self.quest_system:accept(action.quest_id)
            if success then
                -- Could trigger notification here
            end
        end
    elseif action.type == "complete_quest" or action.type == "turn_in_quest" then
        if self.quest_system and action.quest_id then
            local success, rewards = self.quest_system:turnIn(action.quest_id)
            if success then
                -- Could trigger reward notification here
            end
        end
    -- Add more action types as needed:
    -- elseif action.type == "give_item" then
    --     -- inventory:addItem(action.item_id, action.count)
    -- elseif action.type == "remove_item" then
    --     -- inventory:removeItem(action.item_id, action.count)
    -- elseif action.type == "give_gold" then
    --     -- player.gold = player.gold + action.amount
    end
end

return dialogue

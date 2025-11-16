-- systems/dialogue.lua
-- Advanced dialogue system with choice support
-- Supports: Simple messages (Talkies), Choice trees, Quests, Rewards

local Talkies = require "vendor.talkies"
local skip_button_widget = require "engine.ui.widgets.button.skip"
local next_button_widget = require "engine.ui.widgets.button.next"

local dialogue = {}

function dialogue:initialize(display_module)
    -- Configure Talkies
    Talkies.backgroundColor = { 0, 0, 0, 0.8 }
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
        print("ERROR: Dialogue tree not found: " .. tostring(dialogue_id))
        return
    end
    self:showTree(dialogue_tree)
end

-- Start a dialogue tree (choice-based conversation)
function dialogue:showTree(dialogue_tree)
    if not dialogue_tree or not dialogue_tree.nodes then
        print("ERROR: Invalid dialogue tree")
        return
    end

    -- Reset forced_closed flag (allowing dialogue to open)
    self.forced_closed = false

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
        print("ERROR: Node not found: " .. tostring(node_id))
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
        -- If node has both text and choices, show text first, then choices
        if (node.text or node.pages) then
            -- Pending: show choices after text is read
            self.pending_choices = node.choices
            self.current_choices = nil
        else
            -- No text: show choices immediately
            self.current_choices = node.choices
            self.pending_choices = nil
        end
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
    print("[DEBUG] advanceTree() called")

    if not self.tree_mode then
        print("[DEBUG] Not in tree mode, returning")
        return
    end

    local node = self.current_tree.nodes[self.current_node_id]
    if not node then
        print("[DEBUG] Node not found, clearing")
        self:clear()
        return
    end

    print("[DEBUG] Current node:", self.current_node_id)

    -- PAGED MODE: Handle page navigation
    if self.showing_paged_text and self.current_pages then
        print("[DEBUG] Paged mode - current page:", self.current_page_index, "/", self.total_pages - 1)

        -- Advance to next page
        if self.current_page_index < self.total_pages - 1 then
            self.current_page_index = self.current_page_index + 1
            print("[DEBUG] Moving to page:", self.current_page_index)
            return
        else
            -- Last page reached - show choices or continue
            print("[DEBUG] Last page reached")
            if self.current_choices and #self.current_choices > 0 then
                -- Show choices (stay in paged mode but hide text)
                print("[DEBUG] Showing choices")
                return
            else
                -- No choices - advance to next node or end
                if node.next then
                    print("[DEBUG] Node has next:", node.next)
                    self:_showNode(node.next)
                else
                    print("[DEBUG] No next node, clearing dialogue")
                    self:clear()
                end
                return
            end
        end
    end

    -- TALKIES MODE: Handle Talkies text
    print("[DEBUG] Talkies.isOpen():", Talkies.isOpen())
    print("[DEBUG] Talkies.paused:", Talkies.paused)

    if Talkies.isOpen() and not Talkies.paused then
        print("[DEBUG] Advancing Talkies message")
        Talkies.onAction()
        print("[DEBUG] After Talkies.onAction(), Talkies.isOpen():", Talkies.isOpen())
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
        print("[DEBUG] Activating pending choices")
        self.current_choices = self.pending_choices
        self.pending_choices = nil
        self:_updateButtonVisibility()  -- Hide buttons when choices shown
        return
    end

    -- If node has choices, wait for player to select
    if self.current_choices and #self.current_choices > 0 then
        print("[DEBUG] Node has choices, waiting for selection")
        return
    end

    -- No choices - check for auto-advance
    if node.next then
        print("[DEBUG] Node has next:", node.next)
        self:_showNode(node.next)
    else
        print("[DEBUG] No next node, clearing dialogue")
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

    -- Navigate to next node
    if choice.next then
        Talkies.clearMessages()  -- Clear current message
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
-- LEGACY METHODS (backwards compatible)
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

    -- Only log when state changes
    local prev_visible = self.next_button and self.next_button.visible or false
    if (should_show and not prev_visible) or (not should_show and prev_visible) then
        print("[DEBUG] Button visibility changing - isOpen:", is_open, "talkies_open:", talkies_open, "paged:", is_paged_text, "has_choices:", has_choices, "should_show:", should_show)
    end

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
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4, 4)

    -- Draw border
    love.graphics.setColor(1, 1, 1, 1)
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
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", boxX, titleBoxY, titleBoxW, titleBoxH, 4, 4)

        -- Title border
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", boxX, titleBoxY, titleBoxW, titleBoxH, 4, 4)

        -- Title text
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(speaker, titleX, titleY)
    end

    -- Draw current page text
    local textFont = Talkies.font or love.graphics.getFont()
    love.graphics.setFont(textFont)
    local textX = boxX + padding + 5
    local textY = boxY + padding
    local textWidth = boxW - (2 * padding) - 10

    local currentText = self.current_pages[self.current_page_index + 1] or ""
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(currentText, textX, textY, textWidth, "left")

    -- Draw page indicator (1/3)
    local pageIndicator = string.format("%d/%d", self.current_page_index + 1, self.total_pages)
    local indicatorX = boxX + boxW - padding - textFont:getWidth(pageIndicator)
    local indicatorY = boxY + boxH - padding - textFont:getHeight()
    love.graphics.setColor(0.7, 0.7, 0.7, 1)
    love.graphics.print(pageIndicator, indicatorX, indicatorY)

    -- Reset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Internal: Draw dialogue box background for choices (mimics Talkies style)
function dialogue:_drawDialogueBoxForChoices()
    if not self.display then return end

    local vw, vh = self.display:GetVirtualDimensions()
    local padding = 10
    local boxH = vh / 3 - (2 * padding)
    local boxY = vh - (boxH + padding)
    local boxW = vw - (2 * padding)
    local boxX = padding

    -- Draw background (same as Talkies)
    love.graphics.setColor(0, 0, 0, 0.8)  -- Talkies backgroundColor
    love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 4, 4)

    -- Draw border
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 4, 4)

    -- Reset
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
end

-- Internal: Draw choice buttons
function dialogue:_drawChoices()
    if not self.display then return end

    local vw, vh = self.display:GetVirtualDimensions()
    local choice_count = #self.current_choices
    local choice_height = 35
    local choice_spacing = 8

    -- Calculate dialogue box dimensions (same as Talkies)
    local padding = 10
    local boxH = vh / 3 - (2 * padding)
    local boxY = vh - (boxH + padding)

    -- Choice width: fit inside dialogue box with padding
    local choice_width = vw - (4 * padding)
    local total_height = (choice_height * choice_count) + (choice_spacing * (choice_count - 1))

    -- Position choices inside the dialogue box, near the bottom
    local start_x = 2 * padding
    local start_y = boxY + boxH - total_height - (2 * padding)

    love.graphics.setFont(self.choice_font)

    for i, choice in ipairs(self.current_choices) do
        local y = start_y + ((i - 1) * (choice_height + choice_spacing))
        local is_selected = (i == self.selected_choice_index)

        -- Button background
        if is_selected then
            love.graphics.setColor(0.3, 0.6, 0.9, 0.9)  -- Highlighted
        else
            love.graphics.setColor(0.2, 0.2, 0.2, 0.8)  -- Normal
        end
        love.graphics.rectangle("fill", start_x, y, choice_width, choice_height, 5, 5)

        -- Button border
        if is_selected then
            love.graphics.setColor(0.5, 0.8, 1.0, 1.0)
            love.graphics.setLineWidth(3)
        else
            love.graphics.setColor(0.4, 0.4, 0.4, 1.0)
            love.graphics.setLineWidth(2)
        end
        love.graphics.rectangle("line", start_x, y, choice_width, choice_height, 5, 5)

        -- Button text
        love.graphics.setColor(1, 1, 1, 1)
        local text_y = y + (choice_height - self.choice_font:getHeight()) / 2
        love.graphics.printf(choice.text, start_x + 10, text_y, choice_width - 20, "left")
    end

    love.graphics.setColor(1, 1, 1, 1)
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

    -- Calculate dialogue box dimensions (same as _drawChoices)
    local padding = 10
    local boxH = vh / 3 - (2 * padding)
    local boxY = vh - (boxH + padding)

    -- Choice width and positioning (same as _drawChoices)
    local choice_width = vw - (4 * padding)
    local total_height = (choice_height * choice_count) + (choice_spacing * (choice_count - 1))

    -- Position choices inside the dialogue box, near the bottom
    local start_x = 2 * padding
    local start_y = boxY + boxH - total_height - (2 * padding)

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
    print("[DEBUG] onAction() called - tree_mode:", self.tree_mode)

    if self.tree_mode then
        -- Tree mode: handle choice selection or advance
        if self.current_choices and #self.current_choices > 0 then
            print("[DEBUG] Selecting choice:", self.selected_choice_index)
            self:selectChoice(self.selected_choice_index)
        else
            -- No choices - advance tree
            self:advanceTree()
        end
    else
        -- Legacy mode: advance Talkies and update button state
        print("[DEBUG] Legacy mode - calling Talkies.onAction()")
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
            self:onAction()
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
        self:onAction()
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
            -- Highlight the choice being pressed
            self.selected_choice_index = choice_index
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
        if choice_index then
            -- Select the clicked choice
            self:selectChoice(choice_index)
            return true
        end
    end

    return false
end

-- Handle touch/mouse move
function dialogue:touchMoved(id, x, y)
    if Talkies.isOpen() then
        if self.skip_button then
            self.skip_button:touchMoved(id, x, y)
        end
        if self.next_button then
            self.next_button:touchMoved(id, x, y)
        end
    end
end

return dialogue

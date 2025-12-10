-- engine/ui/screens/container.lua
-- Tabbed container for inventory and quest log

local container = {}

local display = require "engine.core.display"
local coords = require "engine.core.coords"
local fonts = require "engine.utils.fonts"
local shapes = require "engine.utils.shapes"
local input = require "engine.core.input"
local colors = require "engine.utils.colors"
local scene_control = require "engine.core.scene_control"
local ui_constants = require "engine.ui.constants"
local locale = require "engine.core.locale"
local sound_utils = require "engine.utils.sound_utils"

-- Sub-screens
local inventory_screen = require "engine.ui.screens.inventory"
local questlog_screen = require "engine.ui.screens.questlog"

-- Alias for sound utility
local play_sound = sound_utils.play

function container:enter(previous, player_inventory, player, quest_system, initial_tab)
    self.previous_scene = previous
    self.inventory = player_inventory
    self.player = player
    self.quest_system = quest_system

    -- Tab state
    self.tabs = {
        { id = "inventory", label_key = "inventory.title" },
        { id = "questlog", label_key = "quest.title" }
    }

    -- Set initial tab (default: inventory)
    initial_tab = initial_tab or "inventory"
    self.current_tab = initial_tab
    self.current_tab_index = initial_tab == "inventory" and 1 or 2

    -- Hide virtual gamepad when container is open (mobile)
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    -- Set scene context for input priority based on current tab
    input:setSceneContext(self.current_tab)

    -- Initialize fonts (use locale system for proper scaling)
    self.title_font = locale:getFont("info") or love.graphics.getFont()

    -- Close button settings (use shared constants)
    self.close_button_size = ui_constants.CLOSE_BUTTON_SIZE  -- 30
    self.close_button_padding = ui_constants.CLOSE_BUTTON_PADDING  -- 15
    self.close_button_hovered = false

    -- Tab button settings (use shared constants)
    self.tab_height = ui_constants.TAB_HEIGHT  -- 30
    self.tab_button_hovered = nil  -- Track which tab is hovered (nil or tab index)

    -- Color shortcuts
    self.color = {
        panel_bg = colors.for_panel_bg_medium,
        highlight = colors.for_button_selected_border,
        text = colors.for_text_normal,
        text_dim = colors.for_text_dim
    }

    -- Initialize sub-screens
    inventory_screen:enter(self, player_inventory, player)
    questlog_screen:enter(self, quest_system)
end

function container:exit()
    -- Show virtual gamepad when leaving (mobile)
    if input.virtual_gamepad then
        input.virtual_gamepad:show()
    end

    -- Cleanup sub-screens (try both exit and leave for compatibility)
    if inventory_screen.exit then inventory_screen:exit() end
    if inventory_screen.leave then inventory_screen:leave() end
    if questlog_screen.exit then questlog_screen:exit() end
    if questlog_screen.leave then questlog_screen:leave() end
end

-- Alias for compatibility
function container:leave()
    self:exit()
end

function container:resize(w, h)
    -- Resize display
    display:Resize(w, h)

    -- Forward resize to previous scene (gameplay)
    if self.previous_scene and self.previous_scene.resize then
        self.previous_scene:resize(w, h)
    end
end

function container:update(dt)
    -- Update current tab's screen
    if self.current_tab == "inventory" then
        if inventory_screen.update then inventory_screen:update(dt) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.update then questlog_screen:update(dt) end
    end
end

function container:draw()
    local vw, vh = display:GetVirtualDimensions()

    -- Draw previous scene (gameplay)
    if self.previous_scene and self.previous_scene.draw then
        self.previous_scene:draw()
    end

    display:Attach()

    -- Semi-transparent background overlay
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, vw, vh)

    -- Draw tab bar
    self:drawTabBar()

    -- Draw current tab content (they handle their own rendering)
    if self.current_tab == "inventory" then
        -- Inventory draws its own UI
        inventory_screen:draw()
    elseif self.current_tab == "questlog" then
        -- Quest log draws its own UI
        questlog_screen:draw()
    end

    -- Draw close button
    self:drawCloseButton()

    display:Detach()
end

function container:drawTabBar()
    local vw, vh = display:GetVirtualDimensions()
    local tab_width = 130  -- Reduced from 200 to ~2/3
    local tab_spacing = ui_constants.PADDING_MEDIUM  -- 10

    -- Calculate panel position (same as inventory/questlog panels)
    local panel_w = ui_constants.PANEL_WIDTH  -- 720
    local panel_x = (vw - panel_w) / 2

    -- Tabs start from left edge of panel
    local start_x = panel_x + 20  -- 20px from panel left edge
    local start_y = ui_constants.TAB_BAR_Y  -- 20

    for i, tab in ipairs(self.tabs) do
        local x = start_x + (i - 1) * (tab_width + tab_spacing)
        local y = start_y
        local is_active = (i == self.current_tab_index)
        local is_hovered = (self.tab_button_hovered == i)

        -- Tab background
        if is_active then
            love.graphics.setColor(self.color.panel_bg[1], self.color.panel_bg[2], self.color.panel_bg[3], 0.9)
        elseif is_hovered then
            love.graphics.setColor(self.color.highlight[1], self.color.highlight[2], self.color.highlight[3], 0.3)
        else
            love.graphics.setColor(self.color.panel_bg[1], self.color.panel_bg[2], self.color.panel_bg[3], 0.5)
        end
        love.graphics.rectangle("fill", x, y, tab_width, self.tab_height, 5, 5)

        -- Tab border
        if is_active then
            love.graphics.setColor(self.color.highlight[1], self.color.highlight[2], self.color.highlight[3], 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", x, y, tab_width, self.tab_height, 5, 5)
        end

        -- Tab label (translated)
        love.graphics.setFont(self.title_font)
        local label_color = is_active and self.color.text or self.color.text_dim
        love.graphics.setColor(label_color[1], label_color[2], label_color[3], 1)
        local label_text = locale:t(tab.label_key)
        local label_width = self.title_font:getWidth(label_text)
        love.graphics.print(
            label_text,
            x + (tab_width - label_width) / 2,
            y + (self.tab_height - self.title_font:getHeight()) / 2
        )
    end

    -- Draw tab switch hint
    local hint_font = locale:getFont("info") or fonts.info or love.graphics.getFont()
    love.graphics.setFont(hint_font)
    local hint_text = "LB/RB or Q/E: Switch Tabs"
    local hint_width = hint_font:getWidth(hint_text)
    love.graphics.setColor(self.color.text_dim[1], self.color.text_dim[2], self.color.text_dim[3], 0.8)
    love.graphics.print(
        hint_text,
        (vw - hint_width) / 2,
        start_y + self.tab_height + 15
    )
end

function container:drawCloseButton()
    local vw, vh = display:GetVirtualDimensions()

    -- Calculate panel position (same as inventory/questlog panels)
    local panel_w = ui_constants.PANEL_WIDTH  -- 720
    local panel_x = (vw - panel_w) / 2

    -- Close button at right edge of panel
    local x = panel_x + panel_w - self.close_button_size - self.close_button_padding
    local y = ui_constants.TAB_BAR_Y  -- 20, same as tab bar Y position

    shapes:drawCloseButton(x, y, self.close_button_size, self.close_button_hovered)
end

function container:switchTab(tab_index)
    if tab_index < 1 or tab_index > #self.tabs then return end
    if tab_index == self.current_tab_index then return end

    self.current_tab_index = tab_index
    self.current_tab = self.tabs[tab_index].id

    -- Update scene context for input priority
    input:setSceneContext(self.current_tab)

    play_sound("ui", "select")
end

function container:keypressed(key)
    local input = require "engine.core.input"

    -- Close container (toggle or explicit close)
    if input:wasPressed("toggle_inventory", "keyboard", key) or
       input:wasPressed("toggle_questlog", "keyboard", key) or
       input:wasPressed("close_inventory", "keyboard", key) or
       input:wasPressed("close_questlog", "keyboard", key) then
        play_sound("ui", "back")
        scene_control.pop()
        return
    end

    -- Tab switching
    if input:wasPressed("prev_tab", "keyboard", key) then
        -- Previous tab
        local new_index = self.current_tab_index - 1
        if new_index < 1 then new_index = #self.tabs end
        self:switchTab(new_index)
        return
    elseif input:wasPressed("next_tab", "keyboard", key) then
        -- Next tab
        local new_index = self.current_tab_index + 1
        if new_index > #self.tabs then new_index = 1 end
        self:switchTab(new_index)
        return
    end

    -- Delegate to current tab
    if self.current_tab == "inventory" then
        if inventory_screen.keypressed then inventory_screen:keypressed(key) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.keypressed then questlog_screen:keypressed(key) end
    end
end

function container:mousepressed(x, y, button)
    local vx, vy = coords:physicalToVirtual(x, y, display)
    local vw, vh = display:GetVirtualDimensions()

    -- Calculate panel position
    local panel_w = ui_constants.PANEL_WIDTH  -- 720
    local panel_x = (vw - panel_w) / 2

    -- Check close button click
    local close_x = panel_x + panel_w - self.close_button_size - self.close_button_padding
    local close_y = ui_constants.TAB_BAR_Y  -- 20

    if vx >= close_x and vx <= close_x + self.close_button_size and
       vy >= close_y and vy <= close_y + self.close_button_size then
        play_sound("ui", "back")
        scene_control.pop()
        return
    end

    -- Check tab clicks
    local tab_width = 130  -- Reduced from 200 to ~2/3
    local tab_spacing = ui_constants.PADDING_MEDIUM  -- 10
    local start_x = panel_x + 20  -- 20px from panel left edge
    local start_y = ui_constants.TAB_BAR_Y  -- 20

    for i, tab in ipairs(self.tabs) do
        local tab_x = start_x + (i - 1) * (tab_width + tab_spacing)
        local tab_y = start_y

        if vx >= tab_x and vx <= tab_x + tab_width and
           vy >= tab_y and vy <= tab_y + self.tab_height then
            self:switchTab(i)
            return
        end
    end

    -- Delegate to current tab
    if self.current_tab == "inventory" then
        if inventory_screen.mousepressed then inventory_screen:mousepressed(x, y, button) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.mousepressed then questlog_screen:mousepressed(x, y, button) end
    end
end

function container:mousereleased(x, y, button)
    -- Delegate to current tab
    if self.current_tab == "inventory" then
        if inventory_screen.mousereleased then inventory_screen:mousereleased(x, y, button) end
    end
end

function container:mousemoved(x, y, dx, dy)
    local vx, vy = coords:physicalToVirtual(x, y, display)
    local vw, vh = display:GetVirtualDimensions()

    -- Calculate panel position
    local panel_w = ui_constants.PANEL_WIDTH  -- 720
    local panel_x = (vw - panel_w) / 2

    -- Update close button hover state
    local close_x = panel_x + panel_w - self.close_button_size - self.close_button_padding
    local close_y = ui_constants.TAB_BAR_Y  -- 20

    self.close_button_hovered = (
        vx >= close_x and vx <= close_x + self.close_button_size and
        vy >= close_y and vy <= close_y + self.close_button_size
    )

    -- Update tab hover state
    local tab_width = 130  -- Reduced from 200 to ~2/3
    local tab_spacing = ui_constants.PADDING_MEDIUM  -- 10
    local start_x = panel_x + 20  -- 20px from panel left edge
    local start_y = ui_constants.TAB_BAR_Y  -- 20

    self.tab_button_hovered = nil
    for i, tab in ipairs(self.tabs) do
        local tab_x = start_x + (i - 1) * (tab_width + tab_spacing)
        local tab_y = start_y

        if vx >= tab_x and vx <= tab_x + tab_width and
           vy >= tab_y and vy <= tab_y + self.tab_height then
            self.tab_button_hovered = i
            break
        end
    end

    -- Delegate to current tab
    if self.current_tab == "inventory" then
        if inventory_screen.mousemoved then inventory_screen:mousemoved(x, y, dx, dy) end
    end
end

function container:gamepadpressed(joystick, button)
    local input = require "engine.core.input"

    -- Close container (toggle or explicit close)
    if input:wasPressed("toggle_inventory", "gamepad", button) or
       input:wasPressed("toggle_questlog", "gamepad", button) or
       input:wasPressed("close_inventory", "gamepad", button) or
       input:wasPressed("close_questlog", "gamepad", button) then
        play_sound("ui", "back")
        scene_control.pop()
        return
    end

    -- Tab switching
    if input:wasPressed("prev_tab", "gamepad", button) then
        -- Previous tab
        local new_index = self.current_tab_index - 1
        if new_index < 1 then new_index = #self.tabs end
        self:switchTab(new_index)
        return
    elseif input:wasPressed("next_tab", "gamepad", button) then
        -- Next tab
        local new_index = self.current_tab_index + 1
        if new_index > #self.tabs then new_index = 1 end
        self:switchTab(new_index)
        return
    end

    -- Delegate to current tab
    if self.current_tab == "inventory" then
        if inventory_screen.gamepadpressed then inventory_screen:gamepadpressed(joystick, button) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.gamepadpressed then questlog_screen:gamepadpressed(joystick, button) end
    end
end

function container:gamepadaxis(joystick, axis, value)
    -- Check for R2 trigger to toggle close container
    if axis == "triggerleft" or axis == "triggerright" then
        local action = input:handleGamepadAxis(joystick, axis, value)
        if action == "open_inventory" then
            play_sound("ui", "back")
            scene_control.pop()
            return
        end
    end

    -- Delegate to current tab
    if self.current_tab == "inventory" then
        if inventory_screen.gamepadaxis then inventory_screen:gamepadaxis(joystick, axis, value) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.gamepadaxis then questlog_screen:gamepadaxis(joystick, axis, value) end
    end
end

function container:touchpressed(id, x, y, dx, dy, pressure)
    -- Delegate to mousepressed for UI interactions
    self:mousepressed(x, y, 1)

    -- Delegate to current tab for swipe scrolling
    if self.current_tab == "inventory" then
        if inventory_screen.touchpressed then inventory_screen:touchpressed(id, x, y, dx, dy, pressure) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.touchpressed then questlog_screen:touchpressed(id, x, y, dx, dy, pressure) end
    end
end

function container:touchreleased(id, x, y, dx, dy, pressure)
    -- Delegate to mousereleased for UI interactions
    self:mousereleased(x, y, 1)

    -- Delegate to current tab for swipe scrolling
    if self.current_tab == "inventory" then
        if inventory_screen.touchreleased then inventory_screen:touchreleased(id, x, y, dx, dy, pressure) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.touchreleased then questlog_screen:touchreleased(id, x, y, dx, dy, pressure) end
    end
end

function container:touchmoved(id, x, y, dx, dy, pressure)
    -- Delegate to mousemoved for hover effects
    self:mousemoved(x, y, dx, dy)

    -- Delegate to current tab for swipe scrolling
    if self.current_tab == "inventory" then
        if inventory_screen.touchmoved then inventory_screen:touchmoved(id, x, y, dx, dy, pressure) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.touchmoved then questlog_screen:touchmoved(id, x, y, dx, dy, pressure) end
    end
end

function container:wheelmoved(x, y)
    -- Delegate to current tab
    if self.current_tab == "inventory" then
        if inventory_screen.wheelmoved then inventory_screen:wheelmoved(x, y) end
    elseif self.current_tab == "questlog" then
        if questlog_screen.wheelmoved then questlog_screen:wheelmoved(x, y) end
    end
end

return container

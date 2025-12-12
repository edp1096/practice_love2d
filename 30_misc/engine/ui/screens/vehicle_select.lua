-- engine/ui/screens/vehicle_select.lua
-- Vehicle selection UI overlay for summoning/dismissing owned vehicles

local vehicle_select = {}

local display = require "engine.core.display"
local input = require "engine.core.input"
local ui_constants = require "engine.ui.constants"
local locale = require "engine.core.locale"
local sound_utils = require "engine.utils.sound_utils"
local entity_registry = require "engine.core.entity_registry"
local vehicle_summon = require "engine.systems.vehicle_summon"
local colors = require "engine.utils.colors"
local shapes = require "engine.utils.shapes"

-- Alias for sound utility
local play_sound = sound_utils.play

-- UI Constants
local PANEL_WIDTH = 300
local PANEL_HEIGHT = 250
local ITEM_HEIGHT = 32
local LIST_PADDING = 15
local MAX_VISIBLE = 5

-- Overlay state
vehicle_select.is_open = false

-- Open vehicle selection as overlay
function vehicle_select:open(world, player)
    self.world = world
    self.player = player

    -- Get owned vehicles
    self.vehicles = entity_registry:getOwnedVehicles()
    if #self.vehicles == 0 then
        return false, "no_vehicles"
    end

    -- Check if summoning is allowed
    if not vehicle_summon.settings or not vehicle_summon.settings.allow_summon then
        return false, "summon_disabled"
    end

    -- Hide virtual gamepad
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    -- UI State
    self.selected_index = 1
    self.scroll_offset = 0
    self.hovered_index = nil

    -- Fonts
    self.title_font = locale:getFont("option") or love.graphics.getFont()
    self.item_font = locale:getFont("info") or love.graphics.getFont()

    -- Close button
    self.close_button_size = ui_constants.CLOSE_BUTTON_SIZE
    self.close_button_padding = ui_constants.CLOSE_BUTTON_PADDING
    self.close_button_hovered = false

    -- Joystick cooldown
    self.joystick_cooldown = 0
    self.joystick_repeat_delay = 0.15

    -- Message
    self.message = nil
    self.message_timer = 0
    self.message_duration = 1.5

    self.is_open = true
    play_sound("ui", "open")
    return true
end

-- Check if UI is open
function vehicle_select:isOpen()
    return self.is_open
end

function vehicle_select:update(dt)
    -- Update message timer
    if self.message_timer > 0 then
        self.message_timer = self.message_timer - dt
        if self.message_timer <= 0 then
            self.message = nil
        end
    end

    -- Update joystick cooldown
    if self.joystick_cooldown > 0 then
        self.joystick_cooldown = self.joystick_cooldown - dt
    end

    -- Handle gamepad joystick input
    if input:hasGamepad() and self.joystick_cooldown <= 0 then
        local ly = input:getAxis("lefty")
        if ly < -0.5 then
            self:moveSelection(-1)
            self.joystick_cooldown = self.joystick_repeat_delay
        elseif ly > 0.5 then
            self:moveSelection(1)
            self.joystick_cooldown = self.joystick_repeat_delay
        end
    end
end

function vehicle_select:close()
    play_sound("ui", "close")

    if input.virtual_gamepad then
        input.virtual_gamepad:show()
    end

    self.is_open = false
end

-- Move selection up/down
function vehicle_select:moveSelection(delta)
    local new_index = self.selected_index + delta
    if new_index < 1 then
        new_index = #self.vehicles
    elseif new_index > #self.vehicles then
        new_index = 1
    end

    if new_index ~= self.selected_index then
        self.selected_index = new_index
        play_sound("ui", "move")

        -- Adjust scroll
        if self.selected_index <= self.scroll_offset then
            self.scroll_offset = self.selected_index - 1
        elseif self.selected_index > self.scroll_offset + MAX_VISIBLE then
            self.scroll_offset = self.selected_index - MAX_VISIBLE
        end
    end
end

-- Get display name for vehicle type
function vehicle_select:getVehicleName(vehicle_type)
    local key = "vehicle." .. vehicle_type
    local translated = locale:t(key)
    if translated and translated ~= key then
        return translated
    end
    -- Fallback: capitalize first letter
    return vehicle_type:sub(1, 1):upper() .. vehicle_type:sub(2)
end

-- Select/toggle vehicle
function vehicle_select:selectVehicle()
    local vehicle_type = self.vehicles[self.selected_index]
    if not vehicle_type then return end

    local summoned = vehicle_summon:getSummoned()

    if summoned and summoned.type == vehicle_type then
        -- Dismiss this vehicle
        local success, err = vehicle_summon:dismiss(self.world)
        if success then
            play_sound("ui", "select")
            self.message = locale:t("vehicle.dismissed") or "Dismissed"
            self.message_timer = self.message_duration
        end
    else
        -- Summon this vehicle (will auto-dismiss current if any)
        local new_vehicle, err = vehicle_summon:summon(vehicle_type, self.world, self.player)
        if new_vehicle then
            play_sound("ui", "select")
            self.message = locale:t("vehicle.summoned") or "Summoned"
            self.message_timer = self.message_duration
            self:close()
        elseif err == "cooldown" then
            self.message = locale:t("vehicle.on_cooldown") or "On cooldown"
            self.message_timer = self.message_duration
        elseif err == "not_enough_gold" then
            self.message = locale:t("vehicle.not_enough_gold") or "Not enough gold"
            self.message_timer = self.message_duration
        end
    end
end

function vehicle_select:draw()
    display:Attach()

    local vw, vh = display:GetVirtualDimensions()

    -- Dim overlay
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, vw, vh)

    -- Panel position
    local panel_x = (vw - PANEL_WIDTH) / 2
    local panel_y = (vh - PANEL_HEIGHT) / 2

    -- Panel background
    love.graphics.setColor(colors.for_panel_bg or {0.15, 0.15, 0.2, 0.95})
    love.graphics.rectangle("fill", panel_x, panel_y, PANEL_WIDTH, PANEL_HEIGHT, 8, 8)

    -- Panel border
    love.graphics.setColor(colors.for_panel_border or {0.4, 0.4, 0.5, 1})
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", panel_x, panel_y, PANEL_WIDTH, PANEL_HEIGHT, 8, 8)

    -- Title
    love.graphics.setFont(self.title_font)
    love.graphics.setColor(1, 1, 1, 1)
    local title = locale:t("vehicle.title") or "Vehicles"
    local title_width = self.title_font:getWidth(title)
    love.graphics.print(title, panel_x + (PANEL_WIDTH - title_width) / 2, panel_y + 12)

    -- Get current summoned vehicle
    local summoned = vehicle_summon:getSummoned()

    -- Vehicle list
    local list_y = panel_y + 50
    love.graphics.setFont(self.item_font)

    for i = 1, math.min(MAX_VISIBLE, #self.vehicles - self.scroll_offset) do
        local idx = i + self.scroll_offset
        local vehicle_type = self.vehicles[idx]
        local item_y = list_y + (i - 1) * ITEM_HEIGHT

        local is_summoned = summoned and summoned.type == vehicle_type
        local is_selected = idx == self.selected_index
        local is_hovered = idx == self.hovered_index

        -- Hover highlight
        if is_hovered and not is_selected then
            love.graphics.setColor(0.25, 0.3, 0.35, 0.6)
            love.graphics.rectangle("fill", panel_x + LIST_PADDING, item_y + 2, PANEL_WIDTH - LIST_PADDING * 2, ITEM_HEIGHT - 4, 3, 3)
        end

        -- Selection highlight
        if is_selected then
            love.graphics.setColor(0.3, 0.4, 0.5, 0.8)
            love.graphics.rectangle("fill", panel_x + LIST_PADDING, item_y + 2, PANEL_WIDTH - LIST_PADDING * 2, ITEM_HEIGHT - 4, 3, 3)
        end

        -- Vehicle name
        if is_summoned then
            love.graphics.setColor(0.5, 1, 0.5, 1)  -- Green for summoned
        else
            love.graphics.setColor(1, 1, 1, 1)
        end
        local name = self:getVehicleName(vehicle_type)
        love.graphics.print(name, panel_x + 25, item_y + 7)

        -- Status
        if is_summoned then
            love.graphics.setColor(0.5, 1, 0.5, 0.8)
            local status = locale:t("vehicle.active") or "[Active]"
            love.graphics.print(status, panel_x + PANEL_WIDTH - self.item_font:getWidth(status) - 25, item_y + 7)
        end
    end

    -- Scroll indicators
    if self.scroll_offset > 0 then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print("^", panel_x + PANEL_WIDTH / 2 - 3, list_y - 12)
    end
    if self.scroll_offset + MAX_VISIBLE < #self.vehicles then
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print("v", panel_x + PANEL_WIDTH / 2 - 3, list_y + MAX_VISIBLE * ITEM_HEIGHT)
    end

    -- Message
    if self.message then
        local msg_width = self.item_font:getWidth(self.message) + 24
        local msg_height = 24
        local msg_x = panel_x + (PANEL_WIDTH - msg_width) / 2
        local msg_y = panel_y + PANEL_HEIGHT - 60

        love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
        love.graphics.rectangle("fill", msg_x, msg_y, msg_width, msg_height, 4, 4)
        love.graphics.setColor(1, 1, 0.5, 1)
        love.graphics.print(self.message, msg_x + 12, msg_y + 5)
    end

    -- Hints
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    local hint_y = panel_y + PANEL_HEIGHT - 28
    local hint = "[A] " .. (locale:t("vehicle.hint_select") or "Select") .. "  [B] " .. (locale:t("vehicle.hint_close") or "Close")
    love.graphics.print(hint, panel_x + 20, hint_y)

    -- Close button
    local close_x = panel_x + PANEL_WIDTH - self.close_button_size - self.close_button_padding
    local close_y = panel_y + self.close_button_padding
    shapes:drawCloseButton(close_x, close_y, self.close_button_size, self.close_button_hovered)

    display:Detach()
end

-- Input handlers
function vehicle_select:keypressed(key)
    if key == "escape" or key == "v" then
        self:close()
    elseif key == "up" or key == "w" then
        self:moveSelection(-1)
    elseif key == "down" or key == "s" then
        self:moveSelection(1)
    elseif key == "return" or key == "space" then
        self:selectVehicle()
    end
end

function vehicle_select:gamepadpressed(joystick, button)
    if input:wasPressed("menu_back", "gamepad", button) then
        self:close()
    elseif input:wasPressed("menu_select", "gamepad", button) then
        self:selectVehicle()
    elseif button == "dpup" then
        self:moveSelection(-1)
    elseif button == "dpdown" then
        self:moveSelection(1)
    end
end

function vehicle_select:mousemoved(x, y)
    local vx, vy = display:GetVirtualMousePosition()
    local vw, vh = display:GetVirtualDimensions()
    local panel_x = (vw - PANEL_WIDTH) / 2
    local panel_y = (vh - PANEL_HEIGHT) / 2

    -- Check close button hover
    local close_x = panel_x + PANEL_WIDTH - self.close_button_size - self.close_button_padding
    local close_y = panel_y + self.close_button_padding
    self.close_button_hovered = vx >= close_x and vx <= close_x + self.close_button_size and
                                vy >= close_y and vy <= close_y + self.close_button_size

    -- Check item hover
    local list_y = panel_y + 50
    self.hovered_index = nil

    for i = 1, math.min(MAX_VISIBLE, #self.vehicles - self.scroll_offset) do
        local idx = i + self.scroll_offset
        local item_y = list_y + (i - 1) * ITEM_HEIGHT

        if vx >= panel_x + LIST_PADDING and vx <= panel_x + PANEL_WIDTH - LIST_PADDING and
           vy >= item_y and vy <= item_y + ITEM_HEIGHT then
            self.hovered_index = idx
            break
        end
    end
end

function vehicle_select:mousepressed(x, y, button)
    if button ~= 1 then return end

    local vx, vy = display:GetVirtualMousePosition()
    local vw, vh = display:GetVirtualDimensions()
    local panel_x = (vw - PANEL_WIDTH) / 2
    local panel_y = (vh - PANEL_HEIGHT) / 2

    -- Close button
    if self.close_button_hovered then
        self:close()
        return
    end

    -- Item click
    if self.hovered_index then
        self.selected_index = self.hovered_index
        self:selectVehicle()
    end
end

function vehicle_select:wheelmoved(x, y)
    if y > 0 then
        self:moveSelection(-1)
    elseif y < 0 then
        self:moveSelection(1)
    end
end

function vehicle_select:touchpressed(id, x, y, dx, dy, pressure)
    self:mousepressed(x, y, 1)
end

function vehicle_select:touchmoved(id, x, y, dx, dy, pressure)
    self:mousemoved(x, y)
end

function vehicle_select:touchreleased(id, x, y, dx, dy, pressure)
    -- Handle as mousepressed for simplicity
end

return vehicle_select

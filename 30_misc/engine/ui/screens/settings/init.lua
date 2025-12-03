-- engine/ui/screens/settings/init.lua
-- Settings menu scene - main coordinator

local settings = {}

local scene_control = require "engine.core.scene_control"
local display = require "engine.core.display"
local input = require "engine.core.input"
local fonts = require "engine.utils.fonts"
local convert = require "engine.utils.convert"

-- Import modules
local options_module = require "engine.ui.screens.settings.options"
local render_module = require "engine.ui.screens.settings.render"
local input_module = require "engine.ui.screens.settings.input"

local is_ready = false

function settings:enter(previous, ...)
    self.previous = previous

    -- Get virtual dimensions (960x540 for 16:9)
    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    -- Hide virtual gamepad in settings menu
    if input.virtual_gamepad then
        input.virtual_gamepad:hide()
    end

    -- Use locale-aware fonts (updated when language changes)
    local locale = require "engine.core.locale"
    self.titleFont = locale:getFont("title") or fonts.title
    self.labelFont = locale:getFont("option") or fonts.option
    self.valueFont = locale:getFont("option") or fonts.option
    self.hintFont = locale:getFont("hint") or fonts.hint

    -- Detect mobile platform
    local is_mobile = (love._os == "Android" or love._os == "iOS")

    -- Get monitor information (desktop only)
    if not is_mobile then
        self.monitor_count = love.window.getDisplayCount()
        self.monitors = {}
        for i = 1, self.monitor_count do
            local w, h = love.window.getDesktopDimensions(i)
            table.insert(self.monitors, { index = i, name = i .. " (" .. w .. "x" .. h .. ")" })
        end
    else
        self.monitor_count = 1
    end

    -- Determine current monitor index first
    local current_monitor = 1
    if not is_mobile then
        -- Validate monitor index (reset to 1 if out of range)
        local monitor_index = convert:toInt(APP_CONFIG.monitor, 1)
        if monitor_index > self.monitor_count or monitor_index < 1 then
            monitor_index = 1
            APP_CONFIG.monitor = 1  -- Reset to valid value
            -- Note: Config save on exit will persist this change
        end
        current_monitor = monitor_index
    end
    self.current_monitor_index = current_monitor

    -- Resolution presets (desktop only) - filter by CURRENT monitor
    if not is_mobile then
        self.resolutions = {}
        -- Get current monitor's desktop dimensions
        local max_w, max_h = love.window.getDesktopDimensions(self.current_monitor_index)

        -- Copy and filter resolutions based on current monitor
        for i, res in ipairs(options_module.resolutions) do
            if res.w <= max_w and res.h <= max_h then
                table.insert(self.resolutions, { w = res.w, h = res.h, name = res.name })
            end
        end
    end

    -- Build options list
    self.options = options_module:buildOptions(is_mobile, self.monitor_count)

    self.selected = 1
    self.mouse_over = 0

    -- Current values indices (desktop only)
    if not is_mobile then
        self.current_resolution_index = options_module:findCurrentResolution(self.resolutions)
    end

    -- Volume indices
    self.current_master_volume_index = options_module:findVolumeLevel(require("engine.core.sound").settings.master_volume)
    self.current_bgm_volume_index = options_module:findVolumeLevel(require("engine.core.sound").settings.bgm_volume)
    self.current_sfx_volume_index = options_module:findVolumeLevel(require("engine.core.sound").settings.sfx_volume)

    -- Vibration and deadzone indices
    self.current_vibration_index = options_module:findVibrationStrength()
    self.current_deadzone_index = options_module:findDeadzone()

    -- Layout (adjusted for more items)
    self.layout = {
        title_y = vh * 0.11,
        options_start_y = vh * 0.21,
        option_spacing = 29,
        hint_y = vh - 25,
        label_x = vw * 0.25,
        value_x = vw * 0.65
    }

    is_ready = true
end

function settings:leave()
    -- Save settings when leaving settings screen
    -- Note: Resolution is already saved when changed in options.lua
    -- Here we just save sound/input settings
    local utils = require "engine.utils.util"
    local sound = require "engine.core.sound"

    -- Don't pass resolution_override - use already-set APP_CONFIG values
    utils:SaveConfig(APP_CONFIG, sound.settings, input.settings, nil)
end

function settings:exit()
    -- Cleanup if needed
end

function settings:update(dt)
    local vmx, vmy = display:GetVirtualMousePosition()

    local previous_mouse_over = self.mouse_over
    self.mouse_over = 0
    love.graphics.setFont(self.labelFont)

    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing
        ---@diagnostic disable-next-line: undefined-field
        local text_height = self.labelFont:getHeight()
        local padding = 10

        if vmy >= y - padding and vmy <= y + text_height + padding then
            self.mouse_over = i
            break
        end
    end

    -- Update selection when mouse hovers over a different option
    if self.mouse_over ~= previous_mouse_over and self.mouse_over > 0 then
        self.selected = self.mouse_over
        require("engine.core.sound"):playSFX("menu", "navigate")
    end

    -- Check gamepad axis input for menu navigation (left stick)
    if input:hasGamepad() then
        if input:wasPressed("menu_up") then
            self.selected = self.selected - 1
            if self.selected < 1 then self.selected = #self.options end
            require("engine.core.sound"):playSFX("menu", "navigate")
        elseif input:wasPressed("menu_down") then
            self.selected = self.selected + 1
            if self.selected > #self.options then self.selected = 1 end
            require("engine.core.sound"):playSFX("menu", "navigate")
        end
    end
end

function settings:draw()
    render_module:draw(self)
end

function settings:keypressed(key)
    input_module:keypressed(self, key)
end

function settings:gamepadpressed(joystick, button)
    input_module:gamepadpressed(self, joystick, button)
end

function settings:mousepressed(x, y, button)
    input_module:mousepressed(self, x, y, button)
end

function settings:mousereleased(x, y, button)
    input_module:mousereleased(self, x, y, button)
end

function settings:touchpressed(id, x, y, dx, dy, pressure)
    input_module:touchpressed(self, id, x, y, dx, dy, pressure)
end

function settings:touchreleased(id, x, y, dx, dy, pressure)
    input_module:touchreleased(self, id, x, y, dx, dy, pressure)
end

function settings:resize(w, h)
    display:Resize(w, h)
    if self.previous and self.previous.resize then
        self.previous:resize(w, h)
    end
end

return settings

-- scenes/settings.lua
-- Settings menu scene

local settings = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local utils = require "utils.util"

local is_ready = false

function settings:enter(previous, ...)
    self.previous = previous

    -- Get virtual dimensions (960x540 for 16:9)
    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    -- Create fonts
    self.titleFont = love.graphics.newFont(36)
    self.labelFont = love.graphics.newFont(24)
    self.valueFont = love.graphics.newFont(24)
    self.hintFont = love.graphics.newFont(16)

    -- Resolution presets
    self.resolutions = {
        { w = 640,  h = 360,  name = "640x360" },
        { w = 854,  h = 480,  name = "854x480" },
        { w = 960,  h = 540,  name = "960x540" },
        { w = 1280, h = 720,  name = "1280x720" },
        { w = 1600, h = 900,  name = "1600x900" },
        { w = 1920, h = 1080, name = "1920x1080" },
        { w = 2560, h = 1440, name = "2560x1440" },
        { w = 3840, h = 2160, name = "3840x2160" },
    }

    -- if item of resolution is larger than monitor size, remove it
    for i = #self.resolutions, 1, -1 do
        local res = self.resolutions[i]
        local w, h = love.window.getDesktopDimensions()
        if res.w > w or res.h > h then
            table.remove(self.resolutions, i)
        end
    end

    -- Get monitor information
    self.monitor_count = love.window.getDisplayCount()
    self.monitors = {}
    for i = 1, self.monitor_count do
        local w, h = love.window.getDesktopDimensions(i)
        table.insert(self.monitors, {
            index = i,
            name = i .. " (" .. w .. "x" .. h .. ")"
        })
    end

    -- Settings options - conditionally include Monitor option
    self.options = {
        { name = "Resolution", type = "list" },
        { name = "Fullscreen", type = "toggle" },
    }

    -- Only show Monitor option if multiple monitors exist
    if self.monitor_count > 1 then
        table.insert(self.options, { name = "Monitor", type = "cycle" })
    end

    table.insert(self.options, { name = "Back", type = "action" })

    self.selected = 1
    self.mouse_over = 0

    -- Current values indices
    self.current_resolution_index = self:findCurrentResolution()
    self.current_monitor_index = GameConfig.monitor or 1

    -- Layout
    self.layout = {
        title_y = vh * 0.15,
        options_start_y = vh * 0.28,
        option_spacing = 48,
        hint_y = vh - 40,
        label_x = vw * 0.25,
        value_x = vw * 0.65
    }

    is_ready = true
end

function settings:findCurrentResolution()
    local current_w = GameConfig.width
    local current_h = GameConfig.height

    for i, res in ipairs(self.resolutions) do
        if res.w == current_w and res.h == current_h then
            return i
        end
    end

    return 3 -- Default to 960x540
end

function settings:update(dt)
    local vmx, vmy = screen:GetVirtualMousePosition()

    self.mouse_over = 0
    love.graphics.setFont(self.labelFont)

    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing
        local text_height = self.labelFont:getHeight()
        local padding = 15

        if vmy >= y - padding and vmy <= y + text_height + padding then
            self.mouse_over = i
            break
        end
    end
end

function settings:draw()
    love.graphics.clear(0.1, 0.1, 0.15, 1)
    love.graphics.setColor(1, 1, 1, 1)

    screen:Attach()

    love.graphics.setFont(self.titleFont)
    love.graphics.printf("Settings", 0, self.layout.title_y, self.virtual_width, "center")

    -- Draw settings options
    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing
        local is_selected = (i == self.selected or i == self.mouse_over)

        -- Draw label
        love.graphics.setFont(self.labelFont)
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
        end
        love.graphics.printf(option.name, 0, y, self.layout.label_x, "right")

        -- Draw value
        love.graphics.setFont(self.valueFont)
        if is_selected then
            love.graphics.setColor(1, 1, 0, 1)
        else
            love.graphics.setColor(1, 1, 1, 1)
        end

        local value_text = self:getOptionValue(i)
        if option.type ~= "action" then
            love.graphics.printf(value_text, self.layout.value_x, y, self.virtual_width - self.layout.value_x - 100, "left")
        end

        -- Draw arrows for adjustable options
        if is_selected and option.type ~= "action" then
            love.graphics.setColor(0.5, 0.5, 1, 1)
            local value_width = self.valueFont:getWidth(value_text)
            love.graphics.printf("< >", self.layout.value_x + value_width + 20, y,
                self.virtual_width - self.layout.value_x - value_width - 20, "left")
        end
    end

    -- Controls hint
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)
    love.graphics.printf("Arrow Keys / WASD: Navigate | Left/Right: Change | Enter: Select | ESC: Back",
        0, self.layout.hint_y - 20, self.virtual_width, "center")
    love.graphics.printf("Mouse: Hover and Click (Left: Next, Right: Previous)",
        0, self.layout.hint_y, self.virtual_width, "center")

    screen:Detach()

    screen:ShowDebugInfo()
    screen:ShowVirtualMouse()
end

function settings:getOptionValue(index)
    local option = self.options[index]

    if option.name == "Resolution" then
        return self.resolutions[self.current_resolution_index].name
    elseif option.name == "Fullscreen" then
        return GameConfig.fullscreen and "On" or "Off"
    elseif option.name == "Monitor" then
        return self.monitors[self.current_monitor_index].name
    elseif option.name == "Back" then
        return ""
    end

    return ""
end

function settings:changeOption(direction)
    local option = self.options[self.selected]

    if option.name == "Resolution" then
        self.current_resolution_index = self.current_resolution_index + direction
        if self.current_resolution_index < 1 then
            self.current_resolution_index = #self.resolutions
        elseif self.current_resolution_index > #self.resolutions then
            self.current_resolution_index = 1
        end

        -- Apply resolution
        local res = self.resolutions[self.current_resolution_index]
        GameConfig.width, GameConfig.height = res.w, res.h
        if not GameConfig.fullscreen then
            love.window.updateMode(res.w, res.h, {
                resizable = GameConfig.resizable,
                display = self.current_monitor_index
            })
            screen:CalculateScale()
        end
        utils:SaveConfig(GameConfig)
    elseif option.name == "Fullscreen" then
        screen:ToggleFullScreen()
        GameConfig.fullscreen = screen.is_fullscreen
        if not GameConfig.fullscreen then
            love.window.updateMode(GameConfig.width, GameConfig.height, {
                resizable = GameConfig.resizable,
                display = self.current_monitor_index
            })
            screen:CalculateScale()
        end
        utils:SaveConfig(GameConfig)
    elseif option.name == "Monitor" then
        self.current_monitor_index = self.current_monitor_index + direction
        if self.current_monitor_index < 1 then
            self.current_monitor_index = #self.monitors
        elseif self.current_monitor_index > #self.monitors then
            self.current_monitor_index = 1
        end

        -- Update monitor in config and screen
        GameConfig.monitor = self.current_monitor_index
        screen.window.display = self.current_monitor_index

        if GameConfig.fullscreen then
            -- For fullscreen, disable then re-enable on new monitor
            screen:DisableFullScreen()
            screen:EnableFullScreen()
        else
            -- For windowed mode, calculate centered position on target monitor
            local dx, dy = love.window.getDesktopDimensions(self.current_monitor_index)
            local x = dx / 2 - GameConfig.width / 2
            local y = dy / 2 - GameConfig.height / 2

            screen.window.x = x
            screen.window.y = y

            love.window.updateMode(GameConfig.width, GameConfig.height, {
                resizable = GameConfig.resizable,
                display = self.current_monitor_index
            })
        end

        -- Recalculate screen after monitor change
        screen:CalculateScale()
        utils:SaveConfig(GameConfig)
    end
end

function settings:keypressed(key)
    if key == "up" or key == "w" then
        self.selected = self.selected - 1
        if self.selected < 1 then
            self.selected = #self.options
        end
    elseif key == "down" or key == "s" then
        self.selected = self.selected + 1
        if self.selected > #self.options then
            self.selected = 1
        end
    elseif key == "left" or key == "a" then
        self:changeOption(-1)
    elseif key == "right" or key == "d" then
        self:changeOption(1)
    elseif key == "return" or key == "space" then
        if self.options[self.selected].name == "Back" then
            local menu = require "scenes.menu"
            scene_control.switch(menu)
        else
            self:changeOption(1)
        end
    elseif key == "escape" then
        local menu = require "scenes.menu"
        scene_control.switch(menu)
    end
end

function settings:mousepressed(x, y, button) end

function settings:mousereleased(x, y, button)
    if button == 1 then
        -- Left mouse button
        if self.mouse_over > 0 then
            self.selected = self.mouse_over

            if self.options[self.selected].name == "Back" then
                local menu = require "scenes.menu"
                scene_control.switch(menu)
            else
                self:changeOption(1)
            end
        end
    elseif button == 2 then
        -- Right mouse button
        if self.mouse_over > 0 and self.options[self.mouse_over].type ~= "action" then
            self.selected = self.mouse_over
            self:changeOption(-1)
        end
    end
end

function settings:resize(w, h)
    screen:Resize(w, h)
end

return settings

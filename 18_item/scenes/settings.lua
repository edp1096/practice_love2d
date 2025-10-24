-- scenes/settings.lua
-- Settings menu scene with gamepad settings and sound volume controls

local settings = {}

local scene_control = require "systems.scene_control"
local screen = require "lib.screen"
local utils = require "utils.util"
local input = require "systems.input"
local sound = require "systems.sound"
local constants = require "systems.constants"

local is_ready = false

function settings:enter(previous, ...)
    self.previous = previous

    -- Get virtual dimensions (960x540 for 16:9)
    local vw, vh = screen:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh

    -- Create fonts (slightly smaller for more items)
    self.titleFont = love.graphics.newFont(32)
    self.labelFont = love.graphics.newFont(20)
    self.valueFont = love.graphics.newFont(20)
    self.hintFont = love.graphics.newFont(14)

    -- Detect mobile platform
    local is_mobile = (love._os == "Android" or love._os == "iOS")

    -- Resolution presets (desktop only)
    if not is_mobile then
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
            if res.w > w or res.h > h then table.remove(self.resolutions, i) end
        end
    end

    -- Get monitor information (desktop only)
    if not is_mobile then
        self.monitor_count = love.window.getDisplayCount()
        self.monitors = {}
        for i = 1, self.monitor_count do
            local w, h = love.window.getDesktopDimensions(i)
            table.insert(self.monitors, { index = i, name = i .. " (" .. w .. "x" .. h .. ")" })
        end
    end

    -- Settings options - conditionally include desktop/mobile options
    self.options = {}

    -- Desktop-only options
    if not is_mobile then
        table.insert(self.options, { name = "Resolution", type = "list" })
        table.insert(self.options, { name = "Fullscreen", type = "toggle" })

        -- Only show Monitor option if multiple monitors exist
        if self.monitor_count > 1 then
            table.insert(self.options, { name = "Monitor", type = "cycle" })
        end
    end

    -- Add sound options (both desktop and mobile)
    table.insert(self.options, { name = "Master Volume", type = "percent" })
    table.insert(self.options, { name = "BGM Volume", type = "percent" })
    table.insert(self.options, { name = "SFX Volume", type = "percent" })
    table.insert(self.options, { name = "Mute", type = "toggle" })

    -- Add gamepad settings if controller is connected
    if input:hasGamepad() then
        table.insert(self.options, { name = "Vibration", type = "toggle" })
        table.insert(self.options, { name = "Vibration Strength", type = "percent" })
        table.insert(self.options, { name = "Deadzone", type = "deadzone" })
    end

    -- Add mobile vibration option for Android/iOS
    if is_mobile then
        table.insert(self.options, { name = "Mobile Vibration", type = "toggle" })
    end

    table.insert(self.options, { name = "Back", type = "action" })

    self.selected = 1
    self.mouse_over = 0

    -- Current values indices (desktop only)
    if not is_mobile then
        self.current_resolution_index = self:findCurrentResolution()
        self.current_monitor_index = GameConfig.monitor or 1
    end

    -- Volume presets (0%, 25%, 50%, 75%, 100%)
    self.volume_levels = { 0.0, 0.25, 0.5, 0.75, 1.0 }
    self.current_master_volume_index = self:findVolumeLevel(sound.settings.master_volume)
    self.current_bgm_volume_index = self:findVolumeLevel(sound.settings.bgm_volume)
    self.current_sfx_volume_index = self:findVolumeLevel(sound.settings.sfx_volume)

    -- Vibration strength presets (0%, 25%, 50%, 75%, 100%)
    self.vibration_strengths = { 0.0, 0.25, 0.5, 0.75, 1.0 }
    self.current_vibration_index = self:findVibrationStrength()

    -- Deadzone presets (0.05 ~ 0.30)
    self.deadzones = { 0.05, 0.10, 0.15, 0.20, 0.25, 0.30 }
    self.current_deadzone_index = self:findDeadzone()

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

function settings:findCurrentResolution()
    local current_w = GameConfig.width
    local current_h = GameConfig.height

    for i, res in ipairs(self.resolutions) do
        if res.w == current_w and res.h == current_h then return i end
    end

    return 3 -- Default to 960x540
end

function settings:findVolumeLevel(current_volume)
    for i, volume in ipairs(self.volume_levels) do
        if math.abs(volume - current_volume) < 0.01 then return i end
    end

    return 5 -- Default to 100%
end

function settings:findVibrationStrength()
    local current = input.settings.vibration_strength
    for i, strength in ipairs(self.vibration_strengths) do
        if math.abs(strength - current) < 0.01 then return i end
    end

    return 5 -- Default to 100%
end

function settings:findDeadzone()
    local current = input.settings.deadzone
    for i, dz in ipairs(self.deadzones) do
        if math.abs(dz - current) < 0.01 then return i end
    end

    return 3 -- Default to 0.15
end

function settings:update(dt)
    local vmx, vmy = screen:GetVirtualMousePosition()

    self.mouse_over = 0
    love.graphics.setFont(self.labelFont)

    for i, option in ipairs(self.options) do
        local y = self.layout.options_start_y + (i - 1) * self.layout.option_spacing
        local text_height = self.labelFont:getHeight()
        local padding = 10

        if vmy >= y - padding and vmy <= y + text_height + padding then
            self.mouse_over = i
            break
        end
    end
end

function settings:draw()
    -- Draw previous scene in background if it exists
    if self.previous and self.previous.draw then
        self.previous:draw()
    else
        love.graphics.clear(0.1, 0.1, 0.15, 1)
    end

    -- Draw semi-transparent overlay
    if self.previous then
        screen:Attach()
        love.graphics.setColor(0, 0, 0, 0.9)
        love.graphics.rectangle("fill", 0, 0, self.virtual_width, self.virtual_height)
        screen:Detach()
    end

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
            love.graphics.printf("< >", self.layout.value_x + value_width + 20, y, self.virtual_width - self.layout.value_x - value_width - 20, "left")
        end
    end

    -- Controls hint
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(0.5, 0.5, 0.5, 1)

    local hint_text
    if input:hasGamepad() then
        hint_text = input:getPrompt("menu_back") .. ": Back | " ..
            input:getPrompt("menu_select") .. ": Select | D-Pad/Left-Right: Change"
    else
        hint_text = "ESC: Back | Enter: Select | Arrow/WASD: Navigate | Left-Right: Change"
    end

    love.graphics.printf(hint_text, 0, self.layout.hint_y - 20, self.virtual_width, "center")

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
    elseif option.name == "Master Volume" then
        return string.format("%.0f%%", self.volume_levels[self.current_master_volume_index] * 100)
    elseif option.name == "BGM Volume" then
        return string.format("%.0f%%", self.volume_levels[self.current_bgm_volume_index] * 100)
    elseif option.name == "SFX Volume" then
        return string.format("%.0f%%", self.volume_levels[self.current_sfx_volume_index] * 100)
    elseif option.name == "Mute" then
        return sound.settings.muted and "On" or "Off"
    elseif option.name == "Vibration" then
        return input.settings.vibration_enabled and "On" or "Off"
    elseif option.name == "Mobile Vibration" then
        return input.settings.mobile_vibration_enabled and "On" or "Off"
    elseif option.name == "Vibration Strength" then
        return string.format("%.0f%%", self.vibration_strengths[self.current_vibration_index] * 100)
    elseif option.name == "Deadzone" then
        return string.format("%.2f", self.deadzones[self.current_deadzone_index])
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
            -- CRITICAL: Call resize chain like window resize does
            self:resize(res.w, res.h)
        end
        utils:SaveConfig(GameConfig)

        -- Play navigate sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "Fullscreen" then
        -- CRITICAL FIX: Always call resize chain for both fullscreen and windowed
        screen:ToggleFullScreen()
        GameConfig.fullscreen = screen.is_fullscreen

        -- Get current dimensions (different for fullscreen vs windowed)
        local current_w, current_h
        if GameConfig.fullscreen then
            -- Fullscreen: use desktop dimensions
            current_w, current_h = love.window.getDesktopDimensions(self.current_monitor_index)
        else
            -- Windowed: use config dimensions
            current_w, current_h = GameConfig.width, GameConfig.height
            love.window.updateMode(current_w, current_h, {
                resizable = GameConfig.resizable,
                display = self.current_monitor_index
            })
        end

        screen:CalculateScale()
        -- CRITICAL: Always call resize chain (both fullscreen and windowed)
        -- This propagates to pause → play → camera:zoomTo()
        self:resize(current_w, current_h)

        utils:SaveConfig(GameConfig)

        -- Play navigate sound
        sound:playSFX("menu", "navigate")
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
        -- CRITICAL: Call resize chain
        self:resize(GameConfig.width, GameConfig.height)
        utils:SaveConfig(GameConfig)

        -- Play navigate sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "Master Volume" then
        self.current_master_volume_index = self.current_master_volume_index + direction
        if self.current_master_volume_index < 1 then
            self.current_master_volume_index = #self.volume_levels
        elseif self.current_master_volume_index > #self.volume_levels then
            self.current_master_volume_index = 1
        end

        sound:setMasterVolume(self.volume_levels[self.current_master_volume_index])

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings)

        -- Test sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "BGM Volume" then
        self.current_bgm_volume_index = self.current_bgm_volume_index + direction
        if self.current_bgm_volume_index < 1 then
            self.current_bgm_volume_index = #self.volume_levels
        elseif self.current_bgm_volume_index > #self.volume_levels then
            self.current_bgm_volume_index = 1
        end

        sound:setBGMVolume(self.volume_levels[self.current_bgm_volume_index])

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings)
    elseif option.name == "SFX Volume" then
        self.current_sfx_volume_index = self.current_sfx_volume_index + direction
        if self.current_sfx_volume_index < 1 then
            self.current_sfx_volume_index = #self.volume_levels
        elseif self.current_sfx_volume_index > #self.volume_levels then
            self.current_sfx_volume_index = 1
        end

        sound:setSFXVolume(self.volume_levels[self.current_sfx_volume_index])

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings)

        -- Test sound
        sound:playSFX("menu", "navigate")
    elseif option.name == "Mute" then
        sound:toggleMute()

        -- Sync to GameConfig before saving
        GameConfig.sound.master_volume = sound.settings.master_volume
        GameConfig.sound.bgm_volume = sound.settings.bgm_volume
        GameConfig.sound.sfx_volume = sound.settings.sfx_volume
        GameConfig.sound.muted = sound.settings.muted

        utils:SaveConfig(GameConfig, sound.settings)
    elseif option.name == "Vibration" then
        input:setVibrationEnabled(not input.settings.vibration_enabled)

        -- Test vibration when enabling
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK; input:vibrate(v.duration, v.left, v.right)
        end
    elseif option.name == "Mobile Vibration" then
        input:setMobileVibrationEnabled(not input.settings.mobile_vibration_enabled)

        -- Test vibration when enabling
        if input.settings.mobile_vibration_enabled then
            local v = constants.VIBRATION.ATTACK; input:vibrate(v.duration, v.left, v.right)
        end
    elseif option.name == "Vibration Strength" then
        self.current_vibration_index = self.current_vibration_index + direction
        if self.current_vibration_index < 1 then
            self.current_vibration_index = #self.vibration_strengths
        elseif self.current_vibration_index > #self.vibration_strengths then
            self.current_vibration_index = 1
        end

        input:setVibrationStrength(self.vibration_strengths[self.current_vibration_index])

        -- Test vibration
        if input.settings.vibration_enabled then
            local v = constants.VIBRATION.ATTACK; input:vibrate(v.duration, v.left, v.right)
        end
    elseif option.name == "Deadzone" then
        self.current_deadzone_index = self.current_deadzone_index + direction
        if self.current_deadzone_index < 1 then
            self.current_deadzone_index = #self.deadzones
        elseif self.current_deadzone_index > #self.deadzones then
            self.current_deadzone_index = 1
        end

        input:setDeadzone(self.deadzones[self.current_deadzone_index])
    end
end

function settings:keypressed(key)
    if key == "escape" then
        sound:playSFX("menu", "back")
        scene_control.pop()
    elseif input:wasPressed("menu_up", "keyboard", key) then
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.options end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_down", "keyboard", key) then
        self.selected = self.selected + 1
        if self.selected > #self.options then self.selected = 1 end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_left", "keyboard", key) then
        self:changeOption(-1)
    elseif input:wasPressed("menu_right", "keyboard", key) then
        self:changeOption(1)
    elseif input:wasPressed("menu_select", "keyboard", key) then
        if self.options[self.selected].name == "Back" then
            sound:playSFX("menu", "back")
            scene_control.pop()
        else
            self:changeOption(1)
        end
    end
end

function settings:gamepadpressed(joystick, button)
    if input:wasPressed("menu_back", "gamepad", button) then
        sound:playSFX("menu", "back")
        scene_control.pop()
    elseif input:wasPressed("menu_up", "gamepad", button) then
        self.selected = self.selected - 1
        if self.selected < 1 then self.selected = #self.options end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_down", "gamepad", button) then
        self.selected = self.selected + 1
        if self.selected > #self.options then self.selected = 1 end
        sound:playSFX("menu", "navigate")
    elseif input:wasPressed("menu_left", "gamepad", button) then
        self:changeOption(-1)
    elseif input:wasPressed("menu_right", "gamepad", button) then
        self:changeOption(1)
    elseif input:wasPressed("menu_select", "gamepad", button) then
        if self.options[self.selected].name == "Back" then
            sound:playSFX("menu", "back")
            scene_control.pop()
        else
            self:changeOption(1)
        end
    end
end

function settings:mousepressed(x, y, button) end

function settings:mousereleased(x, y, button)
    if button == 1 then
        -- Left mouse button
        if self.mouse_over > 0 then
            self.selected = self.mouse_over

            if self.options[self.selected].name == "Back" then
                sound:playSFX("menu", "back")
                scene_control.pop()
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
    if self.previous and self.previous.resize then self.previous:resize(w, h) end
end

return settings
